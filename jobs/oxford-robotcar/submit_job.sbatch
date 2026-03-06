#!/bin/bash
#SBATCH --job-name=oxford-robotcar-scrape
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=01:00:00
#SBATCH --mem=4G
#SBATCH --account=vita-uniworld

HOST_DATA_DIR="/work/vita-uniworld/data/raw/oxford-robotcar" 

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

echo "Generating datasets.csv..."
apptainer exec $IMAGE_PATH python get_datasets.py

echo "Scraping data..."
apptainer exec --bind "$HOST_DATA_DIR:/Downloads" $IMAGE_PATH \
    python scrape_mrgdatashare.py \
    --downloads_dir /Downloads \
    --datasets_file datasets.csv \
    --username "$ROBOTCAR_USER" \
    --password "$ROBOTCAR_PASS"