## 2. Core requirements

### 2.1 Technology

Implementation must use:

- `bash` as the main language
- `git`
- `gh`
- `jq`
- `sed`
- `awk`
- `timeout`
- `flock`
- `mktemp`
- `find`
- standard POSIX utilities
- `codex` CLI

### 2.2 Main loop

The agent loops every **20 seconds** and performs, in order:

1. checkout latest commit from `main`,
2. check opened PRs for merge conflicts with `main` and resolve them,
3. check comments starting with `@:robot:` and process them,
4. check assigned issues in **Todo** state from the configured GitHub Project,
5. pick the highest-priority issue,
6. run issue execution flow or refusal flow as appropriate.

### 2.3 Comment reactions

When the agent starts processing a qualifying GitHub comment:

- add `eyes` reaction.

When the agent finishes processing successfully:

- remove `eyes`,
- add `rocket`.

If processing fails:

- best effort remove `eyes`,
- optionally add a failure comment,
- do **not** add `rocket`.

### 2.4 Checkpoints for issue execution

For issue execution:

- `research`, `plan`, and `test` stages must each write a Markdown file locally under `.grkr/<task-name>/`
- those Markdown files must also be posted to the issue as comments
- the local artifacts must allow execution to resume from checkpoints after interruption or failure

### 2.5 Worktree isolation

For all mutating or parallel work, use separate `git worktree`s:

- PR conflict resolution
- `@:robot:` comment processing
- issue execution
- issue refusal flow if it needs repository context or generated local artifacts

The main checkout is used only by the supervisor and never for implementation work.

### 2.6 Error resilience

The main loop must survive:

- Codex failures,
- GitHub API failures,
- Git failures,
- project field lookup failures,
- worktree creation failures,
- shell script runtime errors in worker scripts.

A failed worker must not terminate the supervisor loop.

---

