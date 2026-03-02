#!/bin/bash

WHISPER=/opt/miniconda3/envs/painforwisdom/bin/whisper

# $1 : input file
# $2 : language (English)

TEMP_FILE=/tmp/temp_audio.m4a

if [ -f "$TEMP_FILE" ]; then
    # make sure there is no old temp file
    rm "$TEMP_FILE"
fi

# extract audio first
ffmpeg -i $1 -vn -acodec copy $TEMP_FILE 
$WHISPER $TEMP_FILE --model large --language $2 --output_format txt
