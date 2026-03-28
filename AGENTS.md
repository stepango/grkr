# Repo Instructions

- After any functional change, update `README.md` so the user-facing workflow stays accurate.
- Treat `spec/spec.md` as the canonical spec source.
- Keep the split spec slices under `spec/parts/` in sync by running the spec sync harness before finishing spec-related work.
- Prefer the split spec files for context-heavy tasks instead of loading the full spec blob.
- Preserve existing shell-script conventions in `bin/` and `test/`; keep changes small and explicit.
