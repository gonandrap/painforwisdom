#!/bin/bash
set -euo pipefail

# $1 : input file (video)
# $2 : language (optional; default: English)
# $3 : date (optional; YYYY-MM-DD; default: today)

INPUT_FILE="${1:-}"
LANGUAGE="${2:-English}"
DATE="${3:-$(date +"%Y-%m-%d")}"  # shellcheck disable=SC2016

if [ -z "$INPUT_FILE" ]; then
    echo "Missing input file"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Input file does not exist: $INPUT_FILE"
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg is required but not found in PATH"
    exit 1
fi

INPUT_BASE_DIR="$(dirname "$INPUT_FILE")"
OUTPUT_DIR="$INPUT_BASE_DIR/auto-generated"
mkdir -p "$OUTPUT_DIR"

TARGET_TRANSCRIPT_FILENAME="$OUTPUT_DIR/transcript_${DATE}.txt"
if [ -f "$TARGET_TRANSCRIPT_FILENAME" ]; then
    echo "Target transcript filename exists, creating unique filename"
    i=1
    while [[ -e "$OUTPUT_DIR/transcript_${DATE}_$i.txt" ]]; do
        ((i++))
    done
    TARGET_TRANSCRIPT_FILENAME="$OUTPUT_DIR/transcript_${DATE}_$i.txt"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TEMP_AUDIO_FILE_PATH="$TMP_DIR/audio_for_transcription.mp3"

# Always extract/compress audio first for reliability and consistent behavior.
ffmpeg -y -i "$INPUT_FILE" -vn -ac 1 -ar 16000 -b:a 32k "$TEMP_AUDIO_FILE_PATH" >/dev/null 2>&1

OPENAI_WHISPER_HELPER="/home/gonzalo/.npm-global/lib/node_modules/openclaw/skills/openai-whisper-api/scripts/transcribe.sh"
CONDA_WHISPER="/opt/miniconda3/envs/painforwisdom/bin/whisper"

if [ -f "$OPENAI_WHISPER_HELPER" ]; then
    echo "Using OpenAI Whisper API helper"
    # Helper resolves API key from env/config as configured in the skill.
    bash "$OPENAI_WHISPER_HELPER" "$TEMP_AUDIO_FILE_PATH" --language "$LANGUAGE" --out "$TARGET_TRANSCRIPT_FILENAME" >/dev/null
elif [ -x "$CONDA_WHISPER" ]; then
    echo "Using local conda whisper binary"
    "$CONDA_WHISPER" "$TEMP_AUDIO_FILE_PATH" --model large --language "$LANGUAGE" --output_format txt --output_dir "$TMP_DIR" >/dev/null
    LOCAL_TXT="$TMP_DIR/$(basename "$TEMP_AUDIO_FILE_PATH" .mp3).txt"
    if [ ! -f "$LOCAL_TXT" ]; then
        echo "Whisper completed but transcript was not found"
        exit 1
    fi
    mv "$LOCAL_TXT" "$TARGET_TRANSCRIPT_FILENAME"
elif command -v whisper >/dev/null 2>&1; then
    echo "Using whisper from PATH"
    whisper "$TEMP_AUDIO_FILE_PATH" --model large --language "$LANGUAGE" --output_format txt --output_dir "$TMP_DIR" >/dev/null
    LOCAL_TXT="$TMP_DIR/$(basename "$TEMP_AUDIO_FILE_PATH" .mp3).txt"
    if [ ! -f "$LOCAL_TXT" ]; then
        echo "Whisper completed but transcript was not found"
        exit 1
    fi
    mv "$LOCAL_TXT" "$TARGET_TRANSCRIPT_FILENAME"
else
    echo "No transcription backend available."
    echo "Checked:"
    echo "- OpenAI helper: $OPENAI_WHISPER_HELPER"
    echo "- Conda whisper: $CONDA_WHISPER"
    echo "- whisper in PATH"
    exit 1
fi

echo "✓ Transcript written: $TARGET_TRANSCRIPT_FILENAME"
