## Implementation refused

### Reason class
underspecified

### Why this issue was not implemented
The issue does not define acceptance criteria for the search ranking behavior, and it is unclear whether relevance should prefer title matches, semantic matches, or exact tags.

### What is needed before implementation
- Define expected ranking behavior
- Provide at least 2-3 concrete examples
- Confirm whether search should index archived items

### Suggested next actions
- Update this issue with explicit acceptance criteria, or
- Split the issue into:
  1. define ranking rules
  2. add indexing support
  3. add search UI behavior
```

### 20.5 Project status update

If refusal occurs and `ENABLE_PROJECT_STATUS_UPDATES=true`, the agent must move the project item to:

```text
Backlog
```

If `REFUSAL_REQUIRES_BACKLOG_MOVE=true` and no Backlog state is found, refusal should still be commented, but the worker should log a project-state update failure and mark the result as `refused_with_project_update_error`.

### 20.6 Refusal is resumable

The refusal flow must be resumable. If `refusal.md` already exists and the matching checkpoint comment exists:

- do not repost duplicate comments,
- do not move project status repeatedly if already in Backlog,
- mark issue workflow as refused and complete cleanup.

---

