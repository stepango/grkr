## 8. Startup validation

At startup the supervisor must verify:

1. `gh auth status` succeeds,
2. GitHub token has the required scopes,
3. `git remote get-url origin` matches configured repo,
4. `codex` is installed and runnable,
5. required tools exist: `jq`, `timeout`, `flock`, `git`, `gh`,
6. local `.grkr` directory can be created and written,
7. the configured project contains the required fields and values:
   - `Status`
   - `Todo`
   - `Backlog`
   - `Priority`

If validation fails, the supervisor remains alive but only logs errors and skips mutating operations.

---

