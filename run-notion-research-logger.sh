#!/bin/bash

RUN_DIRECTORY=$1
RESEARCH_REPORT_CSV=$2
echo "Calling notion-research-logger agent with run directory [$RUN_DIRECTORY] and research report csv file [$RESEARCH_REPORT_CSV]"
claude "Use the notion-research-logger agent. Run directory: $RUN_DIRECTORY. Entry file: $RESEARCH_REPORT_FILE. Process this research entries : $(cat $RESEARCH_REPORT_CSV)"

# After agent completes, verify output:
echo "Validating output..."
cat $RUN_DIRECTORY/notion-research-logger/notion-summary.md
