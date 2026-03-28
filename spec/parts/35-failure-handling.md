## 27. Failure handling

### 27.1 Retry classes

Retry automatically:

- GitHub API 5xx
- transient network failures
- `git fetch` failures
- temporary Codex invocation failures

Do not hot-loop retry:

- malformed config
- missing project field configuration
- repeated policy refusal
- persistent project item edit failure due to missing Backlog state
- deterministic repository permission errors

### 27.2 Backoff

Use per-job backoff:

- 1 loop
- 3 loops
- 10 loops
- cap at 1 hour

### 27.3 Refusal vs failure

Important distinction:

- **failure** means the system could not perform its intended workflow
- **refusal** means the system intentionally decided not to implement

Refusal should not consume repeated retry budget unless issue state changes.

---

