## 11. Phase 1: sync latest `main`

### 11.1 Behavior

The first step in every loop updates the supervisor checkout to latest `origin/main`.

Commands:

```bash
git fetch origin "$MAIN_BRANCH" --prune
git checkout "$MAIN_BRANCH"
git reset --hard "origin/$MAIN_BRANCH"
```

Run under `.grkr/locks/main.lock`.

### 11.2 Restriction

No feature work happens in the supervisor checkout.

---

