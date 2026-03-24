#!/bin/bash
#SBATCH --job-name=opendv-youtube-download
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=2:00:00
#SBATCH --mem=6G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=debug

# Define paths following prepare_metadata.sbatch pattern
JOB_DIR=$PWD
OPENDV_DIR="$HOME/DriveAGI/opendv"
VENV_DIR="$JOB_DIR/opendv_venv"
DOWNLOAD_SCRIPT="$OPENDV_DIR/scripts/youtube_download.py"
CONFIG_PATH="$JOB_DIR/configs/download.json"
JSON_PATH="$JOB_DIR/meta/OpenDV-YouTube.json"

HOST_DATA_DIR="/work/vita-uniworld/data/raw/opendv-youtube"
COMPRESS_WAIT_TIME=300  # Wait 5 minutes of no activity before compressing a video

mkdir -p "$HOST_DATA_DIR"

# Function to monitor and compress completed videos
compress_videos() {
    local data_dir="$1"
    local wait_time="$2"
    local compressed_log="$data_dir/.compressed_videos.log"
    
    mkdir -p "$data_dir"
    touch "$compressed_log"
    
    echo "Compression monitor started, checking $data_dir every 60 seconds..."
    
    while true; do
        # Find directories that haven't been compressed yet
        for video_dir in "$data_dir"/*/ ; do
            [ -d "$video_dir" ] || continue
            
            video_name=$(basename "$video_dir")
            
            # Skip if already compressed or if tar file already exists
            if grep -q "^${video_name}$" "$compressed_log" 2>/dev/null; then
                continue
            fi
            
            if [ -f "$data_dir/${video_name}.tar" ]; then
                echo "Warning: tar file already exists for $video_name, skipping compression"
                echo "$video_name" >> "$compressed_log"
                continue
            fi
            
            # Check if directory has been stable (no modifications for COMPRESS_WAIT_TIME seconds)
            last_modified=$(find "$video_dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
            current_time=$(date +%s)
            
            if [ -n "$last_modified" ]; then
                time_diff=$((current_time - ${last_modified%.*}))
                
                if [ $time_diff -gt $wait_time ]; then
                    echo "Compressing stable video: $video_name"
                    
                    # Compress the video directory
                    cd "$data_dir"
                    if tar -cf "${video_name}.tar" "$video_name" 2>/dev/null; then
                        # Verify tar file was created successfully
                        if tar -tf "${video_name}.tar" >/dev/null 2>&1; then
                            TAR_SIZE=$(du -sh "${video_name}.tar" | cut -f1)
                            echo "Successfully compressed $video_name -> ${video_name}.tar ($TAR_SIZE)"
                            echo "Removing source directory $video_name to save inodes..."
                            rm -rf "$video_name"
                            echo "$video_name" >> "$compressed_log"
                        else
                            echo "Error: tar verification failed for $video_name, keeping original directory"
                            rm -f "${video_name}.tar"
                        fi
                    else
                        echo "Error: compression failed for $video_name"
                    fi
                fi
            fi
        done
        
        # Check if all download processes are complete
        if ! pgrep -f "download.py" >/dev/null && ! pgrep -f "yt-dlp" >/dev/null; then
            echo "No active download processes found, performing final compression sweep..."
            sleep 60  # Wait a bit more to ensure everything is settled
            
            # Final compression of any remaining directories
            for video_dir in "$data_dir"/*/ ; do
                [ -d "$video_dir" ] || continue
                video_name=$(basename "$video_dir")
                
                # Skip if already logged or tar already exists
                if ! grep -q "^${video_name}$" "$compressed_log" 2>/dev/null; then
                    if [ -f "$data_dir/${video_name}.tar" ]; then
                        echo "Warning: tar file already exists for $video_name, skipping"
                        echo "$video_name" >> "$compressed_log"
                        continue
                    fi
                    
                    echo "Final compression: $video_name"
                    cd "$data_dir"
                    if tar -cf "${video_name}.tar" "$video_name" 2>/dev/null; then
                        if tar -tf "${video_name}.tar" >/dev/null 2>&1; then
                            TAR_SIZE=$(du -sh "${video_name}.tar" | cut -f1)
                            echo "Successfully compressed $video_name -> ${video_name}.tar ($TAR_SIZE)"
                            echo "Removing source directory $video_name to save inodes..."
                            rm -rf "$video_name"
                            echo "$video_name" >> "$compressed_log"
                        else
                            echo "Error: tar verification failed for $video_name"
                            rm -f "${video_name}.tar"
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

echo "========================================="
echo "OpenDV YouTube Download Job"
echo "========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"
echo "========================================="

# Verify OpenDV directory exists
if [ ! -d "$OPENDV_DIR" ]; then
    echo "Error: OpenDV directory not found at $OPENDV_DIR"
    echo "Please ensure DriveAGI is cloned to $HOME/DriveAGI"
    exit 1
fi

echo "Found OpenDV directory: $OPENDV_DIR"

# Check if download script exists
if [ ! -f "$DOWNLOAD_SCRIPT" ]; then
    echo "Error: youtube_download.py not found at $DOWNLOAD_SCRIPT"
    echo "Please verify the path to the DriveAGI/opendv directory"
    exit 1
fi

echo "Found download script: $DOWNLOAD_SCRIPT"

# Verify virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    echo "Please run prepare_metadata.sbatch first to set up the environment"
    exit 1
fi

echo "Found virtual environment: $VENV_DIR"

# Verify JSON metadata exists
if [ ! -f "$JSON_PATH" ]; then
    echo "Error: Metadata JSON not found at $JSON_PATH"
    echo "Please run prepare_metadata.sbatch first to generate the metadata"
    exit 1
fi

echo "Found metadata JSON: $JSON_PATH"

# Verify config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Config file not found at $CONFIG_PATH"
    exit 1
fi

echo "Found config file: $CONFIG_PATH"

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Create output directory
mkdir -p "$HOST_DATA_DIR"
echo "Output directory: $HOST_DATA_DIR"

# Count total videos in JSON
TOTAL_VIDEOS=$(python3 -c "import json; data=json.load(open('$JSON_PATH')); print(len(data))")
echo "Total videos in metadata: $TOTAL_VIDEOS"

# Create a temporary config with absolute paths
TEMP_CONFIG="$JOB_DIR/temp_download_config.json"
python3 -c "
import json
with open('$CONFIG_PATH', 'r') as f:
    config = json.load(f)
# Update paths to absolute paths
config['root'] = '$HOST_DATA_DIR'
config['video_list'] = '$JSON_PATH'
config['exception_file'] = '$JOB_DIR/download_exceptions.txt'
with open('$TEMP_CONFIG', 'w') as f:
    json.dump(config, f, indent=4)
"

echo "Created temporary config with absolute paths: $TEMP_CONFIG"

# Change to OpenDV directory (required for script execution)
cd "$OPENDV_DIR" || exit 1
echo "Working directory: $(pwd)"

# Start compression monitor in background
compress_videos "$HOST_DATA_DIR" "$COMPRESS_WAIT_TIME" &
COMPRESS_PID=$!
echo "Started compression monitor (PID: $COMPRESS_PID)"

# Run the download script with config file
# The script handles parallel downloads internally using num_workers from config
echo "========================================="
echo "Starting video downloads..."
echo "Config: $TEMP_CONFIG"
echo "Using $TOTAL_VIDEOS videos from $JSON_PATH"
echo "Output: $HOST_DATA_DIR"
echo "========================================="

python3 "$DOWNLOAD_SCRIPT" --config "$TEMP_CONFIG"

DOWNLOAD_EXIT_CODE=$?
echo "Download script completed with exit code: $DOWNLOAD_EXIT_CODE"

# Clean up temporary config
rm -f "$TEMP_CONFIG"

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
echo "  - Compressed videos: $TAR_COUNT"
echo "  - Uncompressed videos: $DIR_COUNT"
echo "  - Total size: $TOTAL_SIZE"
echo "----------------------------------------"
