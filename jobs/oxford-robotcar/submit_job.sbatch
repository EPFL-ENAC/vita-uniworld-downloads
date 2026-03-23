#!/bin/bash
#SBATCH --job-name=oxford-robotcar-scrape
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=168:00:00
#SBATCH --mem=32G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=16
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=parallel

HOST_DATA_DIR="/work/vita-uniworld/data/raw/oxford-robotcar" 
NUM_CPUS=16
COMPRESS_WAIT_TIME=300  # Wait 5 minutes of no activity before compressing a dataset

mkdir -p "$HOST_DATA_DIR"

# Function to monitor and compress completed datasets
compress_datasets() {
    local data_dir="$1"
    local wait_time="$2"
    local compressed_log="$data_dir/.compressed_datasets.log"
    
    mkdir -p "$data_dir"
    touch "$compressed_log"
    
    echo "Compression monitor started, checking $data_dir every 60 seconds..."
    
    while true; do
        # Find directories that haven't been compressed yet
        for dataset_dir in "$data_dir"/*/ ; do
            [ -d "$dataset_dir" ] || continue
            
            dataset_name=$(basename "$dataset_dir")
            
            # Skip if already compressed
            if grep -q "^${dataset_name}$" "$compressed_log" 2>/dev/null; then
                continue
            fi
            
            # Check if directory has been stable (no modifications for COMPRESS_WAIT_TIME seconds)
            last_modified=$(find "$dataset_dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
            current_time=$(date +%s)
            
            if [ -n "$last_modified" ]; then
                time_diff=$((current_time - ${last_modified%.*}))
                
                if [ $time_diff -gt $wait_time ]; then
                    echo "Compressing stable dataset: $dataset_name"
                    
                    # Compress the dataset directory
                    cd "$data_dir"
                    if tar -cf "${dataset_name}.tar" "$dataset_name" 2>/dev/null; then
                        # Verify tar file was created successfully
                        if tar -tf "${dataset_name}.tar" >/dev/null 2>&1; then
                            echo "Successfully compressed $dataset_name ($(du -sh ${dataset_name}.tar | cut -f1))"
                            rm -rf "$dataset_name"
                            echo "$dataset_name" >> "$compressed_log"
                        else
                            echo "Error: tar verification failed for $dataset_name, keeping original"
                            rm -f "${dataset_name}.tar"
                        fi
                    else
                        echo "Error: compression failed for $dataset_name"
                    fi
                fi
            fi
        done
        
        # Check if all download processes are complete
        if ! pgrep -f "scrape_mrgdatashare.py" >/dev/null; then
            echo "No active download processes found, performing final compression sweep..."
            sleep 60  # Wait a bit more to ensure everything is settled
            
            # Final compression of any remaining directories
            for dataset_dir in "$data_dir"/*/ ; do
                [ -d "$dataset_dir" ] || continue
                dataset_name=$(basename "$dataset_dir")
                
                if ! grep -q "^${dataset_name}$" "$compressed_log" 2>/dev/null; then
                    echo "Final compression: $dataset_name"
                    cd "$data_dir"
                    if tar -cf "${dataset_name}.tar" "$dataset_name" 2>/dev/null; then
                        if tar -tf "${dataset_name}.tar" >/dev/null 2>&1; then
                            echo "Successfully compressed $dataset_name ($(du -sh ${dataset_name}.tar | cut -f1))"
                            rm -rf "$dataset_name"
                            echo "$dataset_name" >> "$compressed_log"
                        else
                            rm -f "${dataset_name}.tar"
                        fi
                    fi
                fi
            done
            
            echo "Compression monitor shutting down."
            break
        fi
        
        sleep 60  # Check every minute
    done
}

if [ -f "credentials.env" ]; then
    source credentials.env
else
    echo "Error: credentials.env not found."
    exit 1
fi

IMAGE_PATH="/work/vita-uniworld/images/robotcar-dataset-scraper.sif"

# Create image if it doesn't exist
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Pulling container image..."
    apptainer pull $IMAGE_PATH docker://matthewgadd/robotcar-dataset-scraper:latest
fi

# Generate datasets.csv
echo "Generating datasets.csv..."
srun apptainer exec $IMAGE_PATH python3 /RobotCarDataset-Scraper/get_datasets.py

# Verify datasets.csv was created
if [ ! -f "datasets.csv" ]; then
    echo "Error: datasets.csv generation failed."
    exit 1
fi

# Count total datasets
TOTAL_DATASETS=$(wc -l < datasets.csv)
echo "Total datasets to download: $TOTAL_DATASETS"

# Split datasets.csv into chunks for parallel processing
echo "Splitting datasets into $NUM_CPUS chunks..."
mkdir -p chunks
split -n l/$NUM_CPUS -d datasets.csv chunks/datasets_chunk_

# Start compression monitor in background
compress_datasets "$HOST_DATA_DIR" "$COMPRESS_WAIT_TIME" &
COMPRESS_PID=$!
echo "Started compression monitor (PID: $COMPRESS_PID)"

# Run scraper in parallel on each chunk
echo "Starting parallel data scraping with $NUM_CPUS workers..."
for i in $(seq -w 0 $((NUM_CPUS - 1))); do
    CHUNK_FILE="chunks/datasets_chunk_$i"
    if [ -f "$CHUNK_FILE" ]; then
        echo "Launching worker $i for chunk: $CHUNK_FILE"
        apptainer exec --bind "$HOST_DATA_DIR:/Downloads" $IMAGE_PATH \
            python3 /RobotCarDataset-Scraper/scrape_mrgdatashare.py \
            --downloads_dir /Downloads \
            --datasets_file "$CHUNK_FILE" \
            --username "$ROBOTCAR_USER" \
            --password "$ROBOTCAR_PASS" &
    fi
done

# Wait for all background jobs to complete
echo "Waiting for download workers to complete..."
wait

# Wait for compression monitor to complete its final sweep
echo "Waiting for compression monitor to complete..."
wait $COMPRESS_PID

echo "All downloads and compression completed!"

# Display compression statistics
echo "----------------------------------------"
echo "Compression Summary:"
TAR_COUNT=$(find "$HOST_DATA_DIR" -maxdepth 1 -name "*.tar" -type f 2>/dev/null | wc -l)
DIR_COUNT=$(find "$HOST_DATA_DIR" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l)
TOTAL_SIZE=$(du -sh "$HOST_DATA_DIR" 2>/dev/null | cut -f1)
echo "  - Compressed datasets: $TAR_COUNT"
echo "  - Uncompressed datasets: $DIR_COUNT"
echo "  - Total size: $TOTAL_SIZE"
echo "----------------------------------------"

# Clean up chunk files
rm -rf chunks
