# OpenDV YouTube Video Downloads

This job downloads driving videos from YouTube using the [OpenDV tool](https://github.com/OpenDriveLab/DriveAGI/tree/main/opendv) from the DriveAGI project.

## Prerequisites

1. **DriveAGI repository**: The DriveAGI repository should be cloned:
   ```bash
   cd /home/solleder
   git clone https://github.com/OpenDriveLab/DriveAGI.git
   ```

2. **Metadata files**: Place the OpenDV-YouTube metadata CSV file in the `meta` subfolder:
   - `jobs/opendv-youtube/meta/OpenDV-YouTube.csv`
   
   You can obtain this file [from the DriveAGI repository](https://docs.google.com/spreadsheets/d/1bHWWP_VXeEe5UzIG-QgKFBdH7mNlSC4GFSJkEhFnt2I)

## Setup

### Step 1: Prepare Metadata and Environment

Run the preparation script to set up the Python virtual environment and preprocess metadata:

```bash
cd jobs/opendv-youtube
sbatch prepare_metadata.sbatch
```

This script will:
- Create a Python virtual environment (`opendv_venv/`)
- Install dependencies from `DriveAGI/opendv/requirements.txt`
- Run `meta_preprocess.py` to generate `meta/OpenDV-YouTube.json` from the CSV file in `meta/OpenDV-YouTube.csv`

Monitor the preparation job:
```bash
tail -f ../../logs/opendv-prepare-metadata_JOBID.out
```

### Step 2: Run the Download Job

Once metadata preparation is complete, submit the main download job:

```bash
cd jobs/opendv-youtube
sbatch submit_job.sbatch
```

## How It Works

1. **Metadata Preparation**: The `prepare_metadata.sbatch` script sets up the environment and processes the OpenDV-YouTube metadata CSV into JSON format
2. **Parallel Downloads**: The main script uses the processed metadata to download videos in parallel (16 workers)
3. **Automatic Compression**: A background monitor compresses completed video directories into tar files to save inodes
4. **Resource Management**: Uses 16 CPUs with 32GB RAM for parallel processing

## Output

Downloaded videos will be stored in:
- **Location**: `/work/vita-uniworld/data/raw/opendv-youtube/`
- **Format**: Compressed tar files (e.g., `video_id.tar`)

Original directories are removed after successful compression to minimize inode usage.

## Monitoring

Check job progress:
```bash
# View output log
tail -f ../../logs/opendv-youtube-download_JOBID.out

# View error log
tail -f ../../logs/opendv-youtube-download_JOBID.err

# Check downloads
ls -lh /work/vita-uniworld/data/raw/opendv-youtube/
```
