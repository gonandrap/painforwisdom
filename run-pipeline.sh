#!/bin/bash
# Usage:
#   ./run_pipeline.sh [--yes] [--no-input] <directory|file>
# Examples:
#   ./run_pipeline.sh ./bulk-ingestion-up-to-feb-27/
#   ./run_pipeline.sh --yes ./bulk-ingestion-up-to-feb-27/
#   ./run_pipeline.sh ./bulk-ingestion-up-to-feb-27/transcript_2026-02-10.txt
#   ./run_pipeline.sh ./runs/2026-02-17_run.mp4

set -euo pipefail

AUTO_YES=false
NO_INPUT=false
INPUT=""

# Set CLAUDE_CMD to override invocation, e.g.:
#   CLAUDE_CMD="claude --dangerously-skip-permissions"
CLAUDE_CMD_DEFAULT="claude --permission-mode dontAsk"
CLAUDE_CMD="${CLAUDE_CMD:-$CLAUDE_CMD_DEFAULT}"
read -r -a CLAUDE_ARR <<< "$CLAUDE_CMD"

usage() {
    cat <<EOH
Usage: ./run_pipeline.sh [--yes] [--no-input] <directory|file>

Options:
  --yes       Auto-confirm bulk processing prompts.
  --no-input  Non-interactive mode for this wrapper (skip local prompts).
              Note: Claude-side pauses for approvals are still handled by Claude flow.
  -h, --help  Show this help.
EOH
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            AUTO_YES=true
            shift
            ;;
        --no-input)
            NO_INPUT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "✗ Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            INPUT="$1"
            shift
            ;;
    esac
done

if [ -z "${INPUT:-}" ]; then
    usage
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
        return
    fi

    # Last fallback: use file modified date.
    if [ -f "$1" ]; then
        date -r "$1" +"%Y-%m-%d"
    fi
}

find_latest_transcript_for_date() {
    local base_dir="$1"
    local date="$2"
    local latest
    latest=$(ls -1t "$base_dir"/auto-generated/transcript_"$date"*.txt 2>/dev/null | head -n1 || true)
    echo "$latest"
}

capture_transcript_candidates() {
    local base_dir="$1"
    local date="$2"
    local out_file="$3"
    ls -1 "$base_dir"/auto-generated/transcript_"$date"*.txt 2>/dev/null | sort > "$out_file" || true
}

find_new_transcript_for_date() {
    local base_dir="$1"
    local date="$2"
    local before_file="$3"
    local newest

    newest=$(ls -1t "$base_dir"/auto-generated/transcript_"$date"*.txt 2>/dev/null \
        | grep -vxF -f "$before_file" \
        | head -n1 || true)

    echo "$newest"
}

confirm_bulk() {
    local count="$1"
    if [ "$AUTO_YES" = true ] || [ "$NO_INPUT" = true ]; then
        return 0
    fi

    read -r -p "Process all ${count} files? (yes/no): " CONFIRM
    [ "$CONFIRM" = "yes" ]
}

# Video detection and transcript extraction
if [ -f "$INPUT" ] && is_video "$INPUT"; then
    DATE=$(extract_date_from_filename "$INPUT")
    if [ -z "$DATE" ]; then
        echo "✗ Could not extract a YYYY-MM-DD date from filename: $INPUT"
        exit 1
    fi

    BEFORE_LIST=$(mktemp)
    capture_transcript_candidates "$(dirname "$INPUT")" "$DATE" "$BEFORE_LIST"

    echo "Video detected. Extracting transcript (date: $DATE)..."
    "${CLAUDE_ARR[@]}" -p "/extract-transcription \"$INPUT\" en $DATE"

    TRANSCRIPT=$(find_new_transcript_for_date "$(dirname "$INPUT")" "$DATE" "$BEFORE_LIST")
    rm -f "$BEFORE_LIST"

    if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
        echo "✗ No NEW transcript was generated for this video/date ($DATE)."
        echo "  Refusing to fall back to older transcripts to avoid processing the wrong file."
        exit 1
    fi

    INPUT="$TRANSCRIPT"
    echo "✓ Transcript extracted: $INPUT"
fi

run_file() {
    local FILE="$1"
    local DATE
    DATE=$(basename "$FILE" .txt | sed 's/transcript_//')

    echo "Processing: $FILE"
    "${CLAUDE_ARR[@]}" "Run the content pipeline on this transcript. Date: $DATE. Transcript file: $FILE. Transcript: $(cat "$FILE")"
}

# if the original INPUT was a video file, then INPUT will refer to the transcript extracted
if [ -f "$INPUT" ]; then
    run_file "$INPUT"

elif [ -d "$INPUT" ]; then
    # Build explicit processing queue; do not infer "latest" transcript for a date.
    FILES=""

    for f in "$INPUT"/*; do
        [ -f "$f" ] || continue

        if is_video "$f"; then
            DATE=$(extract_date_from_filename "$f")
            if [ -z "$DATE" ]; then
                echo "✗ Could not extract date from video: $f"
                exit 1
            fi

            BEFORE_LIST=$(mktemp)
            capture_transcript_candidates "$(dirname "$f")" "$DATE" "$BEFORE_LIST"

            echo "Video found: $(basename "$f") — extracting transcript (date: $DATE)..."
            "${CLAUDE_ARR[@]}" -p "/extract-transcription \"$f\" en $DATE"

            TRANSCRIPT=$(find_new_transcript_for_date "$(dirname "$f")" "$DATE" "$BEFORE_LIST")
            rm -f "$BEFORE_LIST"

            if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
                echo "✗ No NEW transcript generated for video: $f"
                echo "  Refusing to use older transcripts for that date."
                exit 1
            fi

            echo "✓ Transcript extracted: $TRANSCRIPT"
            FILES+="$TRANSCRIPT"$'\n'

        elif [[ "$(basename "$f")" == transcript_*.txt ]]; then
            FILES+="$f"$'\n'
        fi
    done

    FILES=$(echo "$FILES" | sed '/^$/d' | awk -F/ '{print $NF, $0}' | sort | cut -d' ' -f2-)

    if [ -z "$FILES" ]; then
        echo "✗ No files to process in $INPUT (expected videos and/or transcript_*.txt)"
        exit 1
    fi

    echo "Files to process:"
    echo "$FILES" | nl
    echo ""

    COUNT=$(echo "$FILES" | wc -l | xargs)
    if ! confirm_bulk "$COUNT"; then
        echo "Aborted."
        exit 0
    fi

    while IFS= read -r FILE; do
        run_file "$FILE"
    done <<< "$FILES"

    echo ""
    echo "✓ Bulk ingestion complete."

else
    echo "✗ Input is not a valid file or directory: $INPUT"
    exit 1
fi
