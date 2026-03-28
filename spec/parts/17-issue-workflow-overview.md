## 15. Issue workflow overview

The issue workflow is a staged pipeline executed in one dedicated worktree.

Stages:

1. `research`
2. `plan`
3. `implement_or_refuse`
4. `test` (only if implementation proceeds)

The key change is that **implementation is optional**. After research and plan, the agent may decide to:

- continue into implementation, or
- refuse implementation and move the issue back to **Backlog** with a reasoned comment.

### 15.1 High-level outcomes

Possible issue workflow outcomes:

- **implemented**: code changes produced and tested
- **refused**: issue intentionally not implemented
- **blocked**: execution interrupted by transient or external problem
- **failed**: workflow bug or unrecoverable execution failure

### 15.2 Refusal is not failure

A refusal is a valid and expected result when the issue should not be implemented yet.

It must be recorded clearly, commented publicly, checkpointed locally, and reflected in project state.

---

