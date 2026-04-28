# Berkeley Deep Drive 100k dataset

This file describes how to access the [BDD100k](https://github.com/bdd100k/bdd100k) dataset, consisting of 100k videos for a total weight of 1.8 To.

## Downloading the data

To download the data

```bash
cd jobs/bdd100k && sbatch download_bdd100k.sbatch
```

The result will be a single zip file with all the videos.

## Decompressing the data

To decompress the zipped file:

```bash
sbatch decompress_bdd100k.sbatch
```