#!/bin/bash
#SBATCH --job-name=bdd100k-download
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=168:00:00
#SBATCH --mem=4G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=serial

# Configuration
# DOWNLOAD_URL="http://bdd1.ist.berkeley.edu.bdd100k/bdd100k_videos.zip"
DOWNLOAD_URL="http://128.32.162.150/bdd100k/bdd100k_videos.zip"
OUTPUT_DIR="/work/vita-uniworld/data/raw/bdd100k"
OUTPUT_FILE="$OUTPUT_DIR/bdd100k_videos.zip"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "================================================"
echo "BDD100k Dataset Download"
echo "================================================"
echo "URL: $DOWNLOAD_URL"
echo "Output: $OUTPUT_FILE"
echo "Start time: $(date)"
echo "================================================"

# Download the dataset using wget with resume capability
wget -c \
    --progress=dot:giga \
    --timeout=60 \
    --tries=0 \
    --retry-connrefused \
    --output-document="$OUTPUT_FILE" \
    "$DOWNLOAD_URL"

# Check if download was successful
if [ $? -eq 0 ]; then
    echo "================================================"
    echo "Download completed successfully!"
    echo "End time: $(date)"
    echo "File size: $(du -h $OUTPUT_FILE | cut -f1)"
    echo "================================================"
    
    # Verify the file is a valid zip
    echo "Verifying zip file integrity..."
    if unzip -t "$OUTPUT_FILE" > /dev/null 2>&1; then
        echo "✓ Zip file verification passed"
    else
        echo "✗ Warning: Zip file may be corrupted"
        exit 1
    fi
else
    echo "================================================"
    echo "Error: Download failed!"
    echo "End time: $(date)"
    echo "================================================"
    exit 1
fi

echo "Job completed successfully!"
