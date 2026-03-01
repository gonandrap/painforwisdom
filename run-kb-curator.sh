#!/bin/bash

RUN_DIRECTORY=$1
COACHING_FILE_TOUGHT=$2
DATE=$(basename $FILE .txt | sed 's/transcript_//')
VAULT_PATH=./obsidian-vault
echo "Calling kb_curator agent with run directory [$RUN_DIRECTORY] and coaching file thought [$COACHING_FILE_TOUGHT]"
claude "Use the kb-curator agent. Date: $DATE. Run directory: $RUN_DIRECTORY. Vault path: $VAULT_PATH. Coaching tought : $(cat $COACHING_FILE_TOUGHT)"

# After agent completes, verify output:
echo "Validating output..."
cat $RUN_DIRECTORY/kb-curator/curator_summary.md
