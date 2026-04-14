#!/bin/bash
#SBATCH --job-name=opendv-prepare-metadata
#SBATCH --output=../../logs/%x_%j.out
#SBATCH --error=../../logs/%x_%j.err
#SBATCH --time=02:00:00
#SBATCH --mem=8G
#SBATCH --account=vita-uniworld
#SBATCH --cpus-per-task=4
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --qos=debug

echo "========================================="
echo "OpenDV Metadata Preparation Job"
echo "========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"
echo "========================================="

# Define paths
JOB_DIR=$PWD
OPENDV_DIR="$HOME/DriveAGI/opendv"
VENV_DIR="$JOB_DIR/opendv_venv"
REQUIREMENTS_FILE="$JOB_DIR/jobs/opendv-youtube/requirements.txt"
META_PREPROCESS_SCRIPT="$OPENDV_DIR/scripts/meta_preprocess.py"
CSV_PATH="$JOB_DIR/jobs/opendv-youtube/meta/OpenDV-YouTube.csv"
JSON_PATH="$JOB_DIR/jobs/opendv-youtube/meta/OpenDV-YouTube.json"

# Verify DriveAGI/opendv exists
if [ ! -d "$OPENDV_DIR" ]; then
    echo "Error: OpenDV directory not found at $OPENDV_DIR"
    echo "Please ensure DriveAGI is cloned to $HOME/DriveAGI"
    exit 1
fi

echo "Found OpenDV directory: $OPENDV_DIR"

# Change to opendv directory
cd "$OPENDV_DIR" || exit 1
echo "Working directory: $(pwd)"

# Verify requirements.txt exists
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "Error: requirements.txt not found at $REQUIREMENTS_FILE"
    exit 1
fi

echo "Found requirements.txt"

# Create meta directory if it doesn't exist
mkdir -p "$JOB_DIR/jobs/opendv-youtube/meta"
echo "Meta directory: $JOB_DIR/meta"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create virtual environment"
        exit 1
    fi
    echo "Virtual environment created successfully"
else
    echo "Using existing virtual environment at $VENV_DIR"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies from requirements.txt..."
pip install -r "$REQUIREMENTS_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to install dependencies"
    exit 1
fi

echo "Dependencies installed successfully"

# Verify meta_preprocess.py exists
if [ ! -f "$META_PREPROCESS_SCRIPT" ]; then
    echo "Error: meta_preprocess.py not found at $META_PREPROCESS_SCRIPT"
    exit 1
fi

echo "Found meta preprocessing script"

# Verify CSV exists
if [ ! -f "$CSV_PATH" ]; then
    echo "Error: OpenDV-YouTube.csv not found at $CSV_PATH"
    exit 1
fi

echo "Found input CSV: $CSV_PATH"

# Run meta preprocessing
echo "========================================="
echo "Running metadata preprocessing..."
echo "Input CSV: $CSV_PATH"
echo "Output JSON: $JSON_PATH"
echo "========================================="

python3 "$META_PREPROCESS_SCRIPT" \
    --csv_path "$CSV_PATH" \
    --json_path "$JSON_PATH"

if [ $? -ne 0 ]; then
    echo "Error: Metadata preprocessing failed"
    exit 1
fi

# Verify JSON was created
if [ ! -f "$JSON_PATH" ]; then
    echo "Error: Output JSON file was not created at $JSON_PATH"
    exit 1
fi

echo "========================================="
echo "Metadata preprocessing completed successfully!"
echo "Output JSON: $JSON_PATH"
echo "JSON file size: $(du -h "$JSON_PATH" | cut -f1)"
echo "Virtual environment: $VENV_DIR"
echo "End time: $(date)"
echo "========================================="

# Deactivate virtual environment
deactivate