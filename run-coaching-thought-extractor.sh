#!/bin/bash

RUN_ID=$1
FILE=$2
DATE=$(basename $FILE .txt | sed 's/transcript_//')
RUN_DIRECTORY="./processed/$RUN_ID/$(basename $FILE .txt)"
echo "Calling coaching-thought-extractor with run_id [$RUN_ID], file [$FILE] and date [$DATE]..."
claude "Use the coaching-thought-extractor agent. Date: $DATE. Run directory: $RUN_DIRECTORY. Transcript file: $(basename $FILE .txt). Transcript content: $(cat $FILE)"

# After agent completes, verify output:
echo "Output file path..."
cat $RUN_DIRECTORY/coaching-thought-extractor/extraction_report.md
