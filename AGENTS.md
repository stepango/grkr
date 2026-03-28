# Repo Instructions

- After any functional change, update `README.md` so the user-facing workflow stays accurate.
- Treat the split spec slices under `spec/parts/` as the canonical spec source.
- Keep `spec/spec.md` as a generated index over `spec/parts/`.
- Run the spec sync harness before finishing spec-related work so the index stays current.
- Prefer the split spec files for context-heavy tasks instead of loading the full spec blob.
- Preserve existing shell-script conventions in `bin/` and `test/`; keep changes small and explicit.
- Keep every file at 1000 lines or fewer. If a change would push a file over the limit, proactively split or extract helpers before finishing.
