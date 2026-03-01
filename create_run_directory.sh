#!/bin/bash

# Set these two variables at the start of each transcript run
DATE=$(date +%Y-%m-%d)
RUN_ID="${DATE}_$(date +%H%M%S)"

# Create the run directory
mkdir -p $(pwd)/processed/$RUN_ID
echo "Run directory: $(pwd)/processed/$RUN_ID"

# Confirm the transcript exists
ls $(pwd)/bulk-ingestion-up-to-feb-27/transcript_*.txt | sort
