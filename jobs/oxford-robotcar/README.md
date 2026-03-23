# Oxfort robotcar dataset

This file describes how to access the [Oxford robotcar dataset](https://robotcar-dataset.robots.ox.ac.uk/datasets/), based on the [RobotCarDataset-Scraper](https://github.com/mttgdd/RobotCarDataset-Scraper).

Before scraping the data, you first need to [create an account](https://mrgdatashare.robots.ox.ac.uk/register/) and have your account validated. Once this is done, create a 

```bash
cp jobs/oxford-robotcar/credentials.env.example jobs/oxford-robotcar/credentials
```

and add your username and password to the example credentials file.

## Running the script

To run the SLURM script

```bash
cd jobs/oxford-robotcar && sbatch submit_job.sbatch
```