#!/bin/bash
#SBATCH --job-name=opendv-youtube-download
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=168:00:00
#SBATCH --mem=32G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=16
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=serial

HOST_DATA_DIR="/work/vita-uniworld/data/raw/opendv-youtube"
NUM_CPUS=16
COMPRESS_WAIT_TIME=300  # Wait 5 minutes of no activity before compressing a video

# Path to DriveAGI repository (adjust if needed)
DRIVEAGI_PATH="../../../DriveAGI"
OPENDV_SCRIPT="$DRIVEAGI_PATH/opendv/scripts/youtube_download.py"

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

# Check if DriveAGI repository exists
if [ ! -d "$DRIVEAGI_PATH" ]; then
    echo "Error: DriveAGI repository not found at $DRIVEAGI_PATH"
    echo "Please clone the repository or adjust DRIVEAGI_PATH variable"
    exit 1
fi

# Check if opendv download script exists
if [ ! -f "$OPENDV_SCRIPT" ]; then
    echo "Error: opendv download script not found at $OPENDV_SCRIPT"
    echo "Please verify the path to the DriveAGI/opendv directory"
    exit 1
fi

# Verify videos.txt exists
if [ ! -f "videos.txt" ]; then
    echo "Error: videos.txt not found."
    echo "Please create a videos.txt file with one YouTube URL per line"
    exit 1
fi

# Count total videos
TOTAL_VIDEOS=$(wc -l < videos.txt)
echo "Total videos to download: $TOTAL_VIDEOS"

# Split videos.txt into chunks for parallel processing
echo "Splitting videos into $NUM_CPUS chunks..."
mkdir -p chunks
split -n l/$NUM_CPUS -d videos.txt chunks/videos_chunk_

# Start compression monitor in background
compress_videos "$HOST_DATA_DIR" "$COMPRESS_WAIT_TIME" &
COMPRESS_PID=$!
echo "Started compression monitor (PID: $COMPRESS_PID)"

# Run video downloads in parallel on each chunk
echo "Starting parallel video downloads with $NUM_CPUS workers..."
DOWNLOAD_PIDS=()
for i in $(seq -w 0 $((NUM_CPUS - 1))); do
    CHUNK_FILE="chunks/videos_chunk_$i"
    if [ -f "$CHUNK_FILE" ]; then
        echo "Launching worker $i for chunk: $CHUNK_FILE"
        
        # Run opendv download script for this chunk
        # Adjust the command based on actual opendv interface
        (
            while IFS= read -r video_url; do
                [ -z "$video_url" ] && continue
                echo "Worker $i: Downloading $video_url"
                python3 "$OPENDV_SCRIPT" --url "$video_url" --output_dir "$HOST_DATA_DIR" || true
            done < "$CHUNK_FILE"
        ) &
        
        DOWNLOAD_PIDS+=($!)
    fi
done

# Wait for all download workers to complete (not compression monitor)
echo "Waiting for download workers to complete..."
for pid in "${DOWNLOAD_PIDS[@]}"; do
    wait $pid
    echo "Download worker (PID: $pid) completed"
done

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

# Clean up chunk files
rm -rf chunks
