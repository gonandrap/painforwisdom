#!/bin/bash

RUN_DIRECTORY=$1
KB_COACHING_FILE_TOUGHT=$2
echo "Calling painforwisdom-writer agent with run directory [$RUN_DIRECTORY] and coaching file thought [$KB_COACHING_FILE_TOUGHT]"
claude "Use the painforwisdom-writer agent. Run directory: $RUN_DIRECTORY. Create a post about this thought : $(sed -n '/## Research/q;p' $KB_COACHING_FILE_TOUGHT)"

# After agent completes, verify output:
echo "Validating output..."
cat $RUN_DIRECTORY/painforwisdom-writer/blog_post.md
