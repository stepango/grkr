## 20. Refusal flow

If the decision is `refuse`, the agent must enter the refusal flow.

### 20.1 Required actions

1. generate `refusal.md`
2. post `refusal.md` as an issue comment
3. move the project item from `Todo` to `Backlog`
4. mark workflow status as `refused`
5. skip implementation
6. skip test
7. cleanup the worktree

### 20.2 Refusal markdown file

Write:

```text
.grkr/tasks/<slug>/refusal.md
```

The file must contain:

- refusal summary
- refusal class
- detailed reasoning
- what information or prerequisite is missing
- explicit next step recommendations
- whether the issue should be split
- whether follow-up issues are recommended

### 20.3 Refusal classes

Allowed refusal classes:

- `underspecified`
- `too_large`
- `missing_dependency`
- `needs_design_decision`
- `unsafe_autonomous_change`
- `repo_not_ready`
- `other`

### 20.4 Required refusal comment format

Example:

```markdown
<!-- grkr:checkpoint stage=refusal task=issue-123-add-search-index version=1 -->
