## 9. State model

### 9.1 Durable state

Persist in `.grkr/state/`:

- `processed_comments.json`
- `active_jobs.json`
- `project_cache.json`
- `last_comment_scan_at`
- `pr_cache.json`

### 9.2 Job keys

Use stable job keys:

- `pr:<number>:conflict-resolution`
- `comment:<comment_id>`
- `issue:<number>:execution`
- `issue:<number>:refusal`

### 9.3 Idempotency

Do not schedule a duplicate job if:

- the same job is already active, or
- the same entity version has already been completed successfully.

For comment jobs, the version key must include:

- `comment_id`
- `updated_at`
- `sha256(body)`

For issue refusal, the version key should include:

- `issue_number`
- latest issue body/comment digest
- relevant project field values

This prevents duplicate refusal comments on unchanged issue state.

---

