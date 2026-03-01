#!/bin/bash
# Usage:
#   ./run_pipeline.sh ./bulk-ingestion-up-to-feb-27/
#   ./run_pipeline.sh ./bulk-ingestion-up-to-feb-27/transcript_2026-02-10.txt

INPUT=$1

if [ -z "$INPUT" ]; then
    echo "Usage: ./run_pipeline.sh <directory|file>"
    exit 1
fi

run_file() {
    local FILE=$1
    local DATE=$(basename $FILE .txt | sed 's/transcript_//')
    local RUN_ID="${DATE}_$(date +%H%M%S)"

    echo "Processing: $FILE"
    claude "Run the content pipeline on this transcript. Date: $DATE. Transcript file: $FILE. Transcript: $(cat $FILE)"
}

if [ -f "$INPUT" ]; then
    run_file "$INPUT"

elif [ -d "$INPUT" ]; then
    FILES=$(ls $INPUT/transcript_*.txt 2>/dev/null | sort)

    if [ -z "$FILES" ]; then
        echo "✗ No transcript_*.txt files found in $INPUT"
        exit 1
    fi

    echo "Files to process:"
    echo "$FILES" | nl
    echo ""
    read -p "Process all $(echo "$FILES" | wc -l | xargs) files? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    for FILE in $FILES; do
        run_file "$FILE"
    done

    echo ""
    echo "✓ Bulk ingestion complete."

else
    echo "✗ Input is not a valid file or directory: $INPUT"
    exit 1
fi
