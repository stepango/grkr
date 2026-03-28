## 29. Security and policy constraints

The shell wrapper is the real policy boundary.

Mandatory safeguards:

- never execute arbitrary shell fragments from comments,
- only allow predefined command execution paths,
- no writes outside repo/worktree except `.grkr`,
- no force-push to protected branches by default,
- no secret exfiltration,
- redact secrets in logs,
- no automatic implementation when the issue is too ambiguous or risky.

The new refusal path is a safety feature, not just a workflow feature.

---

