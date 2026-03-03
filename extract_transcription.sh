#!/bin/bash

WHISPER=/opt/miniconda3/envs/painforwisdom/bin/whisper

# $1 : input file
# $2 : language (English)
# $3 : date (YYYY-MM-DD)

TEMP_AUDIO_FILENAME=temp_audio.m4a
TEMP_AUDIO_FILE_PATH=/tmp/$TEMP_AUDIO_FILENAME

INPUT_FILE=$1
if [ -z "$INPUT_FILE" ]; then
    echo "Missing input file"
    exit -1
fi

LANGUAGE="$2"
if [ -z "$2" ]; then
    echo "Language not specified, using English"
    LANGUAGE=English
fi

DATE="$3"
if [ -z "$DATE" ]; then
    DATE=$(date +"%Y-%m-%d")
fi

if [ -f "$TEMP_AUDIO_FILE_PATH" ]; then
    # make sure there is no old temp file
    rm "$TEMP_AUDIO_FILE_PATH"
fi

# extract audio first
ffmpeg -i $1 -vn -acodec copy $TEMP_AUDIO_FILE_PATH 
$WHISPER $TEMP_AUDIO_FILE_PATH --model large --language "$LANGUAGE" --output_format txt --output_dir .

INPUT_FILE_NO_EXTENSION=$(basename "${INPUT_FILE%%.*}")
INPUT_BASE_DIR=$(dirname "${INPUT_FILE}")

TARGET_TRANSCRIPT_FILENAME=$INPUT_BASE_DIR/transcript-$DATE.txt
if [ -f "$TARGET_TRANSCRIPT_FILENAME" ]; then
    echo "Target transcript filename exists, creating unique filename"

    i=1
    # Loop until a non-existent filename is found
    while [[ -e "$INPUT_BASE_DIR/transcript-$DATE-$i.txt" ]]; do
        ((i++))
    done
    TARGET_TRANSCRIPT_FILENAME=transcript-$DATE-$i.txt
fi

if [ -f "$TEMP_AUDIO_FILE_PATH" ]; then
    # make sure to not left temp files
    rm "$TEMP_AUDIO_FILE_PATH"
fi
TRANSCRIPT_FILENAME=$(basename $TEMP_AUDIO_FILENAME .m4a).txt
if [ -f "$TRANSCRIPT_FILENAME"  ]; then
    mv $TRANSCRIPT_FILENAME $INPUT_BASE_DIR/$TARGET_TRANSCRIPT_FILENAME
fi
