## 26. Logging and observability

### 26.1 Structured logging

Each log line should include:

- timestamp
- level
- phase
- job key
- entity type/id
- message

Example:

```text
2026-03-27T15:22:00Z INFO phase=issue_execute job=issue:123:execution entity=issue/123 msg="decision=refuse reason_class=underspecified"
```

### 26.2 Worker logs

Each worker writes to:

```text
.grkr/logs/jobs/<job-key>.log
```

### 26.3 Refusal visibility

Refusal must be visible in logs, state, and issue comments. It must never be silently collapsed into generic failure.

---

