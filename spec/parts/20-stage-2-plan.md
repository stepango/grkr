## 18. Stage 2: plan

### 18.1 Inputs

- `research.md`
- issue body/comments
- repository context

### 18.2 Output

Write:

```text
.grkr/tasks/<slug>/plan.md
```

It must contain:

- implementation plan
- files likely to change
- migration or data concerns
- test strategy
- rollback strategy
- out-of-scope items
- refusal assessment section

### 18.3 Required refusal assessment section

`plan.md` must include a section:

```markdown
## Refusal assessment
```

Use the questions defined in [21-refusal-assessment.md](./21-refusal-assessment.md).

### 18.4 Issue checkpoint comment

Post `plan.md` as an issue comment.

### 18.5 Resume rule

If `plan.md` exists and matching checkpoint comment exists, skip this stage unless forced.

---
