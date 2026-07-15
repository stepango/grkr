# bin/lib/linear_mutate.sh
# Guarded live Linear mutation apply helper (sourced by linear_issue.sh).
# Default: everything is dry-run (identical to pre-apply behavior).
# Live apply only when GRKR_LINEAR_MUTATE=1 (literal) + usable token.
# Always returns 0 (soft-fail); use GRKR_LINEAR_MUTATE_STRICT in follow-ups if needed.
# Supports GRKR_LINEAR_APPLY_CMD override for hermetic tests (PATH or direct).
#
# Emits §8 markers:
#   LINEAR_MUTATE=dry-run key=...
#   LINEAR_MUTATE=skipped-no-token key=...
#   LINEAR_MUTATE=applied key=... comment_id=... | state_id=...
#   LINEAR_MUTATE=skipped-already key=...
#   LINEAR_MUTATE=failed key=... error=... (redacted)
#   LINEAR_MUTATE=skipped-no-state-id target=...

maybe_apply_linear_mutation() {
  local dump_file="$1"
  if [ -z "$dump_file" ] || [ ! -f "$dump_file" ]; then
    return 0
  fi

  # Test override: hermetic stub or alt CLI
  if [ -n "${GRKR_LINEAR_APPLY_CMD:-}" ]; then
    # shellcheck disable=SC2086
    ${GRKR_LINEAR_APPLY_CMD} "$dump_file" || true
    return 0
  fi

  # Default: delegate to progress CLI (which does gate + sidecar + POST when allowed)
  local apply_out
  apply_out=$(run_progress_cli linear-apply-mutation "$dump_file" 2>&1) || true
  if [ -n "$apply_out" ]; then
    # Emit marker to stderr for visibility (grep friendly); CLI already prints
    printf '%s\n' "$apply_out" >&2
  fi
  return 0
}
