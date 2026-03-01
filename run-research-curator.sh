#!/bin/bash

RUN_DIRECTORY=$1
KB_COACHING_FILE_TOUGHT=$2
VAULT_PATH=./obsidian-vault
echo "Calling research-curator agent with run directory [$RUN_DIRECTORY] and coaching file thought [$KB_COACHING_FILE_TOUGHT] from the knowledge base"
claude "Use the research-curator agent. Run directory: $RUN_DIRECTORY. Entry file: $KB_COACHING_FILE_TOUGHT. Find related material for this thought : $(cat $KB_COACHING_FILE_TOUGHT)"

# After agent completes, verify output:
echo "Validating output..."
cat $RUN_DIRECTORY/research-curator/research_report.csv
