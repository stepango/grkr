## 5. Configuration

All runtime settings live in:

```bash
.grkr/config.sh
```

Example:

```bash
REPO="owner/repo"
MAIN_BRANCH="main"

PROJECT_OWNER="owner-or-org"
PROJECT_NUMBER="12"

STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
IN_PROGRESS_VALUE="In Progress"
DONE_VALUE="Done"
BACKLOG_VALUE="Backlog"

PRIORITY_FIELD_NAME="Priority"
PRIORITY_MODE="single_select"   # or number
PRIORITY_ORDER="P0,P1,P2,P3"

LOOP_INTERVAL_SECS="20"

COMMENT_PREFIX="@:robot:"

MAX_PARALLEL_COMMENT_JOBS="4"
MAX_PARALLEL_PR_JOBS="2"
ISSUE_EXECUTION_CONCURRENCY="1"

CONFLICT_STRATEGY="rebase"      # or merge

TEST_COMMAND="./scripts/test.sh"
BUILD_COMMAND="./scripts/build.sh"

BOT_GIT_NAME="robot"
BOT_GIT_EMAIL="robot@example.com"

# Coding agent backend (issue decision/implement + line-limit remediation)
GRKR_CODING_AGENT="codex"   # or "grok"
# Optional per-step overrides (else fall back to GRKR_CODING_AGENT):
# GRKR_AGENT_DECISION="grok"
# GRKR_AGENT_IMPLEMENT="codex"
# GRKR_AGENT_REMEDIATE="grok"
CODEX_BIN="codex"
CODEX_MODEL="gpt-5-codex"
CODEX_ARGS="-c model=$CODEX_MODEL"
# GROK_BIN=""                 # default: grok on PATH or ~/.grok/bin/grok
# GROK_MODEL="grok-build"
# GROK_MAX_TURNS="60"
# GROK_ARGS=""                # extra headless flags, e.g. --check

ENABLE_AUTO_PUSH="true"
ENABLE_PROJECT_STATUS_UPDATES="true"
ENABLE_PR_COMMENTS="true"
ENABLE_ISSUE_COMMENTS="true"

KEEP_FAILED_WORKTREES="false"
ALLOW_ISSUE_REFUSAL="true"
REFUSAL_REQUIRES_BACKLOG_MOVE="true"
```

`TODO_VALUE`, `IN_PROGRESS_VALUE`, `DONE_VALUE`, and `BACKLOG_VALUE` are matched against the live project field options case-insensitively after trimming and collapsing whitespace, so config can safely use `In Progress` even when the project option is `In progress`.

`GRKR_CODING_AGENT` selects the coding backend for the shared `run_codex_prompt` bridge (alias `run_coding_agent_prompt`). Default is `codex`. Set `grok` to use Grok Build CLI with the same prompt files and log persistence. Env vars override config when set. `CODEX_ARGS` is passed through on the codex path (was previously documented but unused).

Optional recommended settings:

```bash
MAX_IMPLEMENTATION_ATTEMPTS="1"
MAX_REFUSAL_COMMENT_UPDATES="3"
```

---
