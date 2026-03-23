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

mkdir -p "$HOST_DATA_DIR"

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
wait

echo "All downloads completed!"

# Clean up chunk files
rm -rf chunks
