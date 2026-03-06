#!/bin/bash
#SBATCH --job-name=oxford-robotcar-scrape
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=01:00:00
#SBATCH --mem=4G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=debug
#SBATCH --partition=mig

HOST_DATA_DIR="/work/vita-uniworld/data/raw/oxford-robotcar" 

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

echo "Generating datasets.csv..."
srun apptainer exec $IMAGE_PATH python3 /RobotCarDataset-Scraper/get_datasets.py

echo "Creating test dataset with only the first entry..."
head -n 1 datasets.csv > datasets_test.csv

echo "Scraping data (Test Run)..."
srun apptainer exec --bind "$HOST_DATA_DIR:/Downloads" $IMAGE_PATH \
    python3 /RobotCarDataset-Scraper/scrape_mrgdatashare.py \
    --downloads_dir /Downloads \
    --datasets_file datasets_test.csv \
    --username "$ROBOTCAR_USER" \
    --password "$ROBOTCAR_PASS"
