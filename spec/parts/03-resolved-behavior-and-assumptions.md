## 3. Resolved behavior and assumptions

To make the system implementable, the following behaviors are defined explicitly.

### 3.1 Comment trigger grammar

A GitHub comment is actionable if its trimmed body begins with:

```text
@:robot:
```

Everything after that prefix is treated as the instruction for Codex.

### 3.2 Comment types covered

The base version supports:

- issue comments on issues,
- issue comments on pull requests.

Review comments may be added later but are out of scope for the first version.

### 3.3 Project Todo state

“Todo” means the project item is currently in the configured project field value:

- field: `Status`
- value: `Todo`

Field names and option IDs are loaded dynamically from the project.

### 3.4 Project Backlog state

To support refusal, the project must also define a configured **Backlog** state:

- field: `Status`
- value: `Backlog`

If refusal occurs, the issue is moved from `Todo` to `Backlog`.

### 3.4.1 Project In Progress state

When issue execution is about to begin, the issue should be moved from `Todo` to the configured **In Progress** state before the workflow creates or checks out the issue branch.

Status option resolution should treat configured values case-insensitively and normalize repeated or surrounding whitespace before matching the live project option name.

### 3.5 Priority field

The project priority field may be either:

- numeric, where larger numbers are higher priority, or
- single-select, with configured ordering such as `P0 > P1 > P2 > P3`.

### 3.6 Single active issue execution

By default, the agent executes only **one issue pipeline at a time per repository**.

PR conflict resolution and comment processing may run in parallel up to configured limits.

### 3.7 PR conflict strategy

Conflict resolution uses one configured strategy:

- `rebase` onto `origin/main`, or
- `merge` `origin/main` into the PR branch.

Default: `rebase`.

### 3.8 Issue execution outcome categories

The issue workflow can end in one of these states:

- `complete`
- `failed`
- `blocked`
- `refused`

`refused` is a first-class outcome and is **not** treated as an execution failure.

---
