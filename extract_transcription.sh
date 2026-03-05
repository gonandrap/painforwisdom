#!/bin/bash
# Strict mode:
# -e: stop on command errors
# -u: treat unset vars as errors
# -o pipefail: fail pipeline if any command fails
set -euo pipefail

# $1 : input file (video)
# $2 : language (optional; default: English)
# $3 : date (optional; YYYY-MM-DD; default: today)
#
# Backend selection:
#   WHISPER_BACKEND=local  -> local whisper only (default)
#   WHISPER_BACKEND=openai -> OpenAI API helper only
#   WHISPER_BACKEND=auto   -> local first, then OpenAI helper fallback

INPUT_FILE="${1:-}"
LANGUAGE="${2:-English}"
DATE="${3:-$(date +"%Y-%m-%d")}"  # shellcheck disable=SC2016
WHISPER_BACKEND="${WHISPER_BACKEND:-local}"

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
BREW_WHISPER="/home/linuxbrew/.linuxbrew/bin/whisper"
USR_LOCAL_WHISPER="/usr/local/bin/whisper"

run_local_whisper() {
    if [ -x "$CONDA_WHISPER" ]; then
        echo "Using local conda whisper binary"
        "$CONDA_WHISPER" "$TEMP_AUDIO_FILE_PATH" --model large --language "$LANGUAGE" --output_format txt --output_dir "$TMP_DIR" >/dev/null
    elif command -v whisper >/dev/null 2>&1; then
        echo "Using whisper from PATH"
        whisper "$TEMP_AUDIO_FILE_PATH" --model large --language "$LANGUAGE" --output_format txt --output_dir "$TMP_DIR" >/dev/null
    elif [ -x "$BREW_WHISPER" ]; then
        echo "Using Homebrew whisper binary"
        "$BREW_WHISPER" "$TEMP_AUDIO_FILE_PATH" --model large --language "$LANGUAGE" --output_format txt --output_dir "$TMP_DIR" >/dev/null
    elif [ -x "$USR_LOCAL_WHISPER" ]; then
        echo "Using /usr/local whisper binary"
        "$USR_LOCAL_WHISPER" "$TEMP_AUDIO_FILE_PATH" --model large --language "$LANGUAGE" --output_format txt --output_dir "$TMP_DIR" >/dev/null
    else
        return 1
    fi

    LOCAL_TXT="$TMP_DIR/$(basename "$TEMP_AUDIO_FILE_PATH" .mp3).txt"
    if [ ! -f "$LOCAL_TXT" ]; then
        echo "Whisper completed but transcript was not found"
        exit 1
    fi
    mv "$LOCAL_TXT" "$TARGET_TRANSCRIPT_FILENAME"
    return 0
}

run_openai_whisper() {
    if [ -f "$OPENAI_WHISPER_HELPER" ]; then
        echo "Using OpenAI Whisper API helper"
        bash "$OPENAI_WHISPER_HELPER" "$TEMP_AUDIO_FILE_PATH" --language "$LANGUAGE" --out "$TARGET_TRANSCRIPT_FILENAME" >/dev/null
        return 0
    fi
    return 1
}

case "$WHISPER_BACKEND" in
    local)
        run_local_whisper || {
            echo "Local whisper backend not available."
            echo "Checked:"
            echo "- Conda whisper: $CONDA_WHISPER"
            echo "- whisper in PATH"
            echo "- Homebrew whisper: $BREW_WHISPER"
            echo "- /usr/local whisper: $USR_LOCAL_WHISPER"
            exit 1
        }
        ;;
    openai)
        run_openai_whisper || {
            echo "OpenAI helper backend not available: $OPENAI_WHISPER_HELPER"
            exit 1
        }
        ;;
    auto)
        if ! run_local_whisper; then
            run_openai_whisper || {
                echo "No transcription backend available."
                echo "Checked local + OpenAI helper."
                exit 1
            }
        fi
        ;;
    *)
        echo "Invalid WHISPER_BACKEND: $WHISPER_BACKEND (expected: local|openai|auto)"
        exit 1
        ;;
esac

echo "✓ Transcript written: $TARGET_TRANSCRIPT_FILENAME"
