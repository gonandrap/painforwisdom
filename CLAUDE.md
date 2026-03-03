# Project: Gonzalo's Content Pipeline

## Overview
This project automates the creation of blog posts for painforwisdom.wordpress.com
from raw video transcripts recorded during runs, and builds a structured Obsidian
knowledge base that will serve as the foundation for Gonzalo's book.

## Architecture
The main Claude Code session acts as the orchestrator. Subagents never call each
other. Claude Code invokes each subagent sequentially, collects its output,
verifies it, and passes it as input to the next stage. All pipeline logic lives
here in CLAUDE.md, not inside any subagent.

## Subagents
The following subagents are available in `.claude/agents/`:
- `coaching-thought-extractor` — analyzes transcripts, extracts coaching insights
- `painforwisdom-writer` — writes blog posts mimicking the painforwisdom style
- `kb-curator` — maintains the Obsidian vault and evolves the book outline
- `research-curator` — finds and verifies specific references, saves to vault
- `notion-research-logger` — creates Notion tasks from research reports
- `notion-blog-post-logger` — logs the generated blog post to the Notion "Blog post pending publications" database
- `blog-post-catchy-title` — revisits the blog post title in Notion for marketing appeal while keeping the blog's voice

## Notion
Research Tasks database: https://www.notion.so/64b70c23f694412895b72a383001c0f2
Data source ID: dfd97a4e-0114-4cb8-8f75-658bb2b83b17

---

## PIPELINE ORCHESTRATION

### Run directory

At the start of every pipeline execution, before invoking any subagent, create
a unique run directory and capture the vault path as an absolute path:
```bash
RUN_ID=$(date +%Y-%m-%d_%H%M%S)
VAULT_PATH=$(pwd)/obsidian-vault
mkdir -p ./processed/$RUN_ID
echo $RUN_ID
echo $VAULT_PATH
```

With the RUN_ID, we create the <RUN_DIR>, which basically is "./processed/<RUN_ID>/<INPUT_TRANSCRIPT>"
being <INPUT_TRANSCRIPT> the name of the input transcript file (remember that the pipeline start with 
that file) without the extension. Make sure that directory exist before calling subagent:
```bash
mkdir -p ./processed/$RUN_ID>/$INPUT_TRANSCRIPT
echo $RUN_ID
```

All subagents write their output under this directory. Pass the full dir path
to each subagent as part of their input. The run directory structure will be:
```
./processed/
└── 2026-02-26_143022/
    └─── transcript_2026-02-17/
    	├── coaching-thought-extractor/
	│  └── extraction_report.md
    	├── kb-curator/
    	│  └── curator_summary.md
    	├── painforwisdom-writer/
    	│  └── blog_post.md
    	├── notion-blog-post-logger/
    	│  └── notion_blog_summary.md
    	├── blog-post-catchy-title/
    	│  └── title_update_summary.md
    	├── research-curator/
    	│  └── research_report.csv
    	└── notion-research-logger/
  	    └── notion_summary.md
```

### How to trigger

**Full pipeline (kb + blog post):**
"run the content pipeline on this transcript [paste transcript]"

**KB only, no blog post:**
"run the knowledge base pipeline on this transcript, no blog post needed
Video date: YYYY-MM-DD [paste transcript]"

**Bulk ingestion:**
"process all transcripts in [directory path]"
Files must follow the naming convention: transcript_YYYY-MM-DD.txt
---

### Execution rules (always follow these)

1. Never simulate or describe agent invocations — invoke them as real tool calls
2. Create the run directory before invoking any subagent
3. Pass the full run directory path to every subagent
4. Invoke one subagent at a time — never in parallel
5. After each subagent completes, verify its output file exists on disk
6. Fully read each subagent's output file before invoking the next stage
7. If a required stage fails verification, stop and report — do not continue
8. Pass explicit input to each subagent — never assume they share context
9. **Never fall back to a general-purpose agent when a specialized agent is unavailable.** If a named agent (coaching-thought-extractor, kb-curator, research-curator, notion-research-logger, notion-blog-post-logger, blog-post-catchy-title, painforwisdom-writer) cannot be invoked, stop the pipeline immediately and report which agent failed to load. Do not substitute, approximate, or continue with any other agent type.

---

### Stage 1 — coaching-thought-extractor

**Invoke with:**
- Full transcript text
- Video date
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`
- Transcript file name
- Transcript file content

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/coaching-thought-extractor/extraction_report.md`

**Verify:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/coaching-thought-extractor/extraction_report.md
if [ -f $FILE ]; then
    echo "Summary file exists"
else
    echo "Summary file not found"
fi
```
- File exists and contains Content Quality, Core Insight, Blog Post Seed → continue
- File missing or incomplete → re-invoke extractor once, then stop if still failing

**CRITICAL: Never write or create the extraction_report.md yourself.** If the file is missing, only re-invoke the coaching-thought-extractor agent. Writing the file directly bypasses the extraction logic and corrupts the pipeline.

**Read** the Content Quality field from the file.

**Gate:**
- Flagged → present flag report to Gonzalo, stop, wait for instructions
- Weak or Strong → continue to Stage 2

---

### Stage 2 — kb-curator

**Invoke with:**
- Full content of `./processed/$RUN_ID/$INPUT_TRANSCRIPT/coaching-thought-extractor/extraction_report.md`
- Video date
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`
- Vault path: `$VAULT_PATH` (the absolute path computed at pipeline start, e.g. `/Users/gonzalo.raposo/workspace/painforwisdom/obsidian-vault`)

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/kb-curator/curator_summary.md`

**Verify output file:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/kb-curator/curator_summary.md
if [ -f $FILE ]; then
    echo "exists"
else
    echo "not found"
fi
```
- File exists → continue to vault verification
- File missing → stop pipeline, report failure

**Verify vault side effect:**
```bash
ls ./obsidian-vault/gonzalo-book/entries/YYYY-MM-DD-*.md 2>/dev/null
```
- Entry file exists → continue to Stage 3
- Entry file missing → stop pipeline, report failure

**Note:** kb-curator may pause for theme/framework approval. Surface the request
to Gonzalo, collect the response, pass it back to kb-curator, then continue.

---

### Stage 3 — painforwisdom-writer

**Only runs if:**
- Pipeline mode is Full (not KB only)
- Content Quality in `./processed/$RUN_ID/$INPUT_TRANSCRIPT/coaching-thought-extractor/extraction_report.md` is Strong

**Invoke with:**
- Blog Post Seed field read from `./processed/$RUN_ID/$INPUT_TRANSCRIPT/coaching-thought-extractor/extraction_report.md`
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/painforwisdom-writer/blog_post.md`

**Verify output file:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/painforwisdom-writer/blog_post.md
if [ -f $FILE ]; then
    echo "exists"
else
    echo "not found"
fi
```
- File exists and contains a title and body → present to Gonzalo for review
- File missing or empty → re-invoke writer once, then report

---

### Stage 4 — notion-blog-post-logger

**Only runs if:** Stage 3 (painforwisdom-writer) produced a blog_post.md

**Invoke with:**
- Full content of `./processed/$RUN_ID/$INPUT_TRANSCRIPT/painforwisdom-writer/blog_post.md`
- Video date
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/notion-blog-post-logger/notion_blog_summary.md`

**Verify output file:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/notion-blog-post-logger/notion_blog_summary.md
if [ -f $FILE ]; then
    echo "exists"
else
    echo "not found"
fi
```
- File exists and contains a Notion URL → continue to Stage 5
- File missing → log failure, continue (non-blocking)

---

### Stage 5 — blog-post-catchy-title

**Only runs if:** Stage 4 (notion-blog-post-logger) produced a notion_blog_summary.md with a Notion URL

**Invoke with:**
- Notion page URL read from `./processed/$RUN_ID/$INPUT_TRANSCRIPT/notion-blog-post-logger/notion_blog_summary.md`
- Vault path: `$VAULT_PATH`
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/blog-post-catchy-title/title_update_summary.md`

**Verify output file:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/blog-post-catchy-title/title_update_summary.md
if [ -f $FILE ]; then
    echo "exists"
else
    echo "not found"
fi
```
- File exists → continue to Stage 6
- File missing → log failure, continue (non-blocking)

---

### Stage 6 — research-curator

**Invoke with:**
- Filename of the entry created in Stage 2. Entry file name is $FILE_ENTRY
- Content of $ENTRY_FILE
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/research-curator/research_report.csv`

**Verify output file:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/research-curator/research_report.csv
if [ -f $FILE ]; then
    echo "exists"
else
    echo "not found"
fi
```
- File exists and has at least one data row → continue to Stage 7
- File missing or empty → log as non-blocking failure, continue to Stage 7

**Verify vault side effect:**
```bash
grep -l "## Research" ./obsidian-vault/gonzalo-book/entries/YYYY-MM-DD-*.md
```
- Section exists → continue
- Missing → log as non-blocking failure, continue

---

### Stage 7 — notion-research-logger

**Invoke with:**
- Full contents of `./processed/$RUN_ID/$INPUT_TRANSCRIPT/research-curator/research_report.csv`
- Run directory path: `./processed/$RUN_ID/$INPUT_TRANSCRIPT`

**Agent writes to:** `./processed/$RUN_ID/$INPUT_TRANSCRIPT/notion-research-logger/notion_summary.md`

**Verify output file:**
```bash
FILE=./processed/$RUN_ID/$INPUT_TRANSCRIPT/notion-research-logger/notion_summary.md
if [ -f $FILE ]; then
    echo "exists"
else
    echo "not found"
fi
```
- File exists → read task count from file
- File missing → log failure, continue (non-blocking)

**Verify:** task count in file matches reference count in research_report.csv
- Matches → continue
- Mismatches → log discrepancy, continue (non-blocking)

---

### Final summary

After all stages complete:
```bash
find ./processed/$RUN_ID/$INPUT_TRANSCRIPT -type f | sort
```

Use the actual file listing to confirm what was produced, then report:
```
✓ Pipeline complete — RUN_ID: 20260226_143022

Run directory: ./processed/20260226_143022/transcript_2026-02-10

Stage 1 — extraction:        [✓ extraction_report.md / ✗ failed]  — [Strong/Weak/Flagged]
Stage 2 — kb-curator:        [✓ curator_summary.md + vault entry / ✗ failed]
Stage 3 — blog writer:       [✓ blog_post.md / skipped (Weak) / skipped (KB only)]
Stage 4 — notion blog post:  [✓ notion_blog_summary.md / skipped (no post) / ✗ failed]
Stage 5 — title optimizer:   [✓ title_update_summary.md (N candidates appended) / skipped (no post) / ✗ failed]
Stage 6 — research:          [✓ research_report.csv (N refs) / ✗ failed]
Stage 7 — notion logger:     [✓ notion_summary.md (N tasks) / ✗ failed]

Vault entry: [[YYYY-MM-DD-slug]]
Notion: N new research tasks added
```

---

### Error escalation

| Stage | Failure | Action |
|-------|---------|--------|
| Any | Specialized agent not found or not registered | Stop pipeline immediately, report which agent failed to load — do NOT substitute with general-purpose |
| 1 | Output file missing or incomplete | Re-invoke once, then stop — **never write the file yourself** |
| 1 | Content Flagged | Stop, present flag to Gonzalo, wait |
| 2 | Output file missing | Stop pipeline, report |
| 2 | Vault entry file missing | Stop pipeline, report |
| 3 | Blog post file missing or empty | Re-invoke once, then report |
| 4 | Output file missing | Log, continue (non-blocking) |
| 5 | Output file missing | Log, continue (non-blocking) |
| 6 | Output file missing | Log, continue |
| 6 | Vault research section missing | Log, continue |
| 7 | Output file missing | Log, continue |
| 7 | Task count mismatch | Log, continue |

---


## painforwisdom-writer context
Blog: https://painforwisdom.wordpress.com
Owner: Gonzalo — ultra runner, engineer, father
Style: raw first-person, date-stamped openings, bold key insights, bridges running
with life lessons, ends with earned 1-3 sentence conclusions, 400-600 words,
no headers or bullets in body. Always output a title before the post body.
Tone: grounded and direct, not heroic or dramatic. Reinforce facts and data from
what actually happened — don't exaggerate sensory details or make the experience
sound bigger than it was.
Citations: knows the world of David Goggins, Jocko Willink, Ed Mylett, Les Brown,
Eric Thomas, Tony Robbins, etc. Reference their concepts naturally when relevant,
but cite by name only occasionally and when it adds real power — over-citing feels forced.
