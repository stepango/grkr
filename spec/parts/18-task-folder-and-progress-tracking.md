## 16. Task folder and progress tracking

Task slug example:

```text
issue-123-add-search-index
```

Task folder:

```text
.grkr/tasks/issue-123-add-search-index/
```

Files:

- `meta.env`
- `issue-context.json`
- `research.md`
- `plan.md`
- `refusal.md`
- `implementation.log`
- `test.md`
- `progress.json`

Example `progress.json`:

```json
{
  "issue_number": 123,
  "project_item_id": "PVTI_xxx",
  "task_slug": "issue-123-add-search-index",
  "branch": "robot/issue-123-add-search-index",
  "status": "planning",
  "decision": "undecided",
  "stages": {
    "research": {"status": "done", "comment_id": 1111},
    "plan": {"status": "done", "comment_id": 1112},
    "implement_or_refuse": {"status": "pending"},
    "test": {"status": "pending"}
  },
  "started_at": "...",
  "updated_at": "..."
}
```

If refusal happens:

```json
{
  "status": "refused",
  "decision": "refuse",
  "stages": {
    "research": {"status": "done", "comment_id": 1111},
    "plan": {"status": "done", "comment_id": 1112},
    "implement_or_refuse": {"status": "done", "comment_id": 1113, "reason_class": "underspecified"},
    "test": {"status": "skipped"}
  }
}
```

---

