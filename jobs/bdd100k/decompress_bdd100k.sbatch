#!/bin/bash
#SBATCH --job-name=bdd100k-decompress
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=72:00:00
#SBATCH --mem=6G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=serial

# Configuration
ZIP_FILE="/work/vita-uniworld/data/raw/bdd100k/bdd100k_videos.zip"
OUTPUT_DIR="/work/vita-uniworld/data/raw/bdd100k"

echo "================================================"
echo "BDD100k Dataset Decompression"
echo "================================================"
echo "Input file: $ZIP_FILE"
echo "Output directory: $OUTPUT_DIR"
echo "Start time: $(date)"
echo "================================================"

# Check if zip file exists
if [ ! -f "$ZIP_FILE" ]; then
    echo "Error: Zip file not found: $ZIP_FILE"
    exit 1
fi

# Display file size
echo "Zip file size: $(du -h $ZIP_FILE | cut -f1)"
echo ""

# Check available disk space
AVAILABLE_SPACE=$(df -h "$OUTPUT_DIR" | awk 'NR==2 {print $4}')
echo "Available disk space in output directory: $AVAILABLE_SPACE"
echo ""

# Verify zip file integrity before extraction
echo "Verifying zip file integrity..."
if unzip -t "$ZIP_FILE" > /dev/null 2>&1; then
    echo "✓ Zip file verification passed"
else
    echo "⚠ Warning: Zip file verification failed"
    echo "  This may be a false positive for very large files"
    echo "  Proceeding with extraction anyway..."
fi

echo ""
echo "Starting decompression..."
echo "This may take several hours for a 1.8 TB file..."
echo "Note: Extraction will continue even if some files are corrupted"
echo "Note: Zip bomb detection is DISABLED for this very large file"
echo ""

# Decompress the file with error recovery options
# -o: overwrite files without prompting
# -d: specify output directory
# -qq: very quiet mode (only show errors)
# Note: unzip will extract as much as possible even with corruption
# UNZIP_DISABLE_ZIPBOMB_DETECTION=TRUE disables zip bomb protection for very large files
export UNZIP_DISABLE_ZIPBOMB_DETECTION=TRUE
unzip -o -qq -d "$OUTPUT_DIR" "$ZIP_FILE" 2>&1 | tee "$OUTPUT_DIR/extraction_errors.log"

# Capture the exit code
UNZIP_EXIT=$?

# Check decompression results
# Exit codes: 0=success, 1=warning (some files skipped), 2+=error
echo ""
echo "================================================"
if [ $UNZIP_EXIT -eq 0 ]; then
    echo "Decompression completed successfully!"
elif [ $UNZIP_EXIT -eq 1 ]; then
    echo "Decompression completed with warnings"
    echo "Some files may have been skipped due to corruption"
    echo "Check extraction_errors.log for details"
else
    echo "Decompression encountered errors (exit code: $UNZIP_EXIT)"
    echo "Partial extraction may have succeeded"
    echo "Check extraction_errors.log for details"
fi

echo "End time: $(date)"
echo ""

# Show extracted contents
echo "Extracted contents:"
ls -lh "$OUTPUT_DIR" | head -20
echo ""

# Count extracted files
FILE_COUNT=$(find "$OUTPUT_DIR" -type f -not -name "*.zip" -not -name "*.log" | wc -l)
echo "Number of extracted files: $FILE_COUNT"

# Calculate total size of extracted files
EXTRACTED_SIZE=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
echo "Total directory size: $EXTRACTED_SIZE"
echo "================================================"

# Summary
echo ""
if [ -f "$OUTPUT_DIR/extraction_errors.log" ] && [ -s "$OUTPUT_DIR/extraction_errors.log" ]; then
    echo "⚠ Errors/warnings were logged to: $OUTPUT_DIR/extraction_errors.log"
    echo "Review the log to see which files may be affected"
else
    echo "✓ No errors logged during extraction"
fi

echo ""
echo "Note: You may want to remove the zip file to save space:"
echo "rm $ZIP_FILE"

# Exit with original unzip exit code if it was a serious error
if [ $UNZIP_EXIT -ge 2 ]; then
    exit $UNZIP_EXIT
fi

echo "Job completed successfully!"
