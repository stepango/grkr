## 13. Phase 3: detect and process `@:robot:` comments

### 13.1 Discovery

Scan issue comments on:

- issues
- pull requests

A comment is actionable only if it starts with `@:robot:`.

### 13.2 Reaction flow

Before processing:

- add `eyes`.

On successful completion:

- best effort remove `eyes`,
- add `rocket`.

On failure:

- best effort remove `eyes`,
- optionally add a failure comment,
- do not add `rocket`.

### 13.3 Worker flow

`worker-handle-comment.sh <comment_id>`

1. fetch comment context,
2. add `eyes`,
3. create worktree,
4. build Codex prompt from:
   - raw command,
   - issue/PR title and body,
   - recent comments,
   - current branch context,
   - repo policy,
5. execute chosen action,
6. comment with result if needed,
7. commit and push if needed,
8. update reactions,
9. cleanup.

### 13.4 Supported action classes

Codex may choose one of:

- **answer-only**
- **code-change**
- **triage**
- **refuse**

A refusal in comment handling only affects the comment response. It does not automatically move project items unless explicitly configured.

---

