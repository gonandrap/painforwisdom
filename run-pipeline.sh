#!/bin/bash
# Usage:
#   ./run_pipeline.sh ./bulk-ingestion-up-to-feb-27/
#   ./run_pipeline.sh ./bulk-ingestion-up-to-feb-27/transcript_2026-02-10.txt
#   ./run_pipeline.sh ./runs/2026-02-17_run.mp4

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT=$1

if [ -z "$INPUT" ]; then
    echo "Usage: ./run_pipeline.sh <directory|file>"
    exit 1
fi

is_video() {
    echo "${1##*.}" | grep -qiE "^(mp4|mov|m4v|avi|mkv)$"
}

extract_date_from_filename() {
    local name
    name=$(basename "$1")
    # Try YYYY-MM-DD first
    local d
    d=$(echo "$name" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    if [ -n "$d" ]; then
        echo "$d"
        return
    fi
    # Fall back to YYYYMMDD (e.g. PXL_20260227_...)
    d=$(echo "$name" | grep -oE '[0-9]{8}' | head -1)
    if [ -n "$d" ]; then
        echo "${d:0:4}-${d:4:2}-${d:6:2}"
    fi
}

# Video detection and transcript extraction
if [ -f "$INPUT" ] && is_video "$INPUT"; then
    DATE=$(extract_date_from_filename "$INPUT")
    if [ -z "$DATE" ]; then
        echo "✗ Could not extract a YYYY-MM-DD date from filename: $INPUT"
        exit 1
    fi

    echo "Video detected. Extracting transcript (date: $DATE)..."
    claude -p "/extract-transcription \"$INPUT\" English $DATE"

    TRANSCRIPT="$(dirname "$INPUT")/auto-generated/transcript_${DATE}.txt"

    if [ ! -f "$TRANSCRIPT" ]; then
        echo "✗ Transcript not found after extraction. Expected: $TRANSCRIPT"
        exit 1
    fi

    INPUT="$TRANSCRIPT"
    echo "✓ Transcript extracted: $INPUT"
fi

run_file() {
    local FILE=$1
    local DATE=$(basename $FILE .txt | sed 's/transcript_//')
    local RUN_ID="${DATE}_$(date +%H%M%S)"

    echo "Processing: $FILE"
    claude "Run the content pipeline on this transcript. Date: $DATE. Transcript file: $FILE. Transcript: $(cat $FILE)"
}

# if the original INPUT was a video file, then INPUT will refer to the transcript extracted
if [ -f "$INPUT" ]; then
    run_file "$INPUT"

elif [ -d "$INPUT" ]; then
    # Extract transcripts from any video files in the directory first
    for f in "$INPUT"/*; do
        [ -f "$f" ] || continue
        if is_video "$f"; then
            DATE=$(extract_date_from_filename "$f")
            if [ -z "$DATE" ]; then
                echo "✗ Could not extract date from video: $f — skipping"
                continue
            fi
            TRANSCRIPT="$(dirname "$f")/auto-generated/transcript_${DATE}.txt"
            if [ -f "$TRANSCRIPT" ]; then
                echo "✓ Transcript already exists for $DATE — skipping extraction"
            else
                echo "Video found: $(basename "$f") — extracting transcript (date: $DATE)..."
                claude -p "/extract-transcription \"$f\" English $DATE"
                if [ ! -f "$TRANSCRIPT" ]; then
                    echo "✗ Transcript not found after extraction. Expected: $TRANSCRIPT — skipping"
                else
                    echo "✓ Transcript extracted: $TRANSCRIPT"
                fi
            fi
        fi
    done

    FILES=$(find "$INPUT" -maxdepth 2 -name "transcript_*.txt" 2>/dev/null | \
        awk -F/ '{print $NF, $0}' | sort | cut -d' ' -f2-)

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
