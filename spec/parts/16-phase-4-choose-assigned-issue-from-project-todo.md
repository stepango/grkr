## 14. Phase 4: choose assigned issue from project Todo

### 14.1 Candidate selection

The agent queries the configured project and selects issues that satisfy:

- item type = issue,
- assigned to the bot/authenticated user,
- `Status = Todo`,
- issue is open,
- issue belongs to the configured repo,
- issue is not already active.

### 14.2 Priority ordering

Order by:

1. highest configured priority,
2. oldest update time,
3. lowest issue number.

### 14.3 Scheduling

If no issue execution is already active, schedule the top candidate.

---

