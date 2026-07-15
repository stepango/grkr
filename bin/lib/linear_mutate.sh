# bin/lib/linear_mutate.sh
# Guarded live Linear mutation apply helper (sourced by linear_issue.sh).
# Default: everything is dry-run (identical to pre-apply behavior).
# Live apply only when GRKR_LINEAR_MUTATE=1 (literal) + usable token.
# GRKR_LINEAR_MUTATE_STRICT=1 (literal) turns non-idempotent apply failures into
# hard errors (non-zero return) for non-refuse dumps. Refuse dumps (basename
# matching refusal.*) always stay soft. All skips/dry/applied/idempotent stay soft.
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

  local apply_out=""
  local rc=0

  # Test override: hermetic stub or alt CLI. Capture real rc + output.
  if [ -n "${GRKR_LINEAR_APPLY_CMD:-}" ]; then
    apply_out=$(${GRKR_LINEAR_APPLY_CMD} "$dump_file" 2>&1) || rc=$?
  else
    # Default: delegate to progress CLI (which does gate + sidecar + POST when allowed)
    apply_out=$(run_progress_cli linear-apply-mutation "$dump_file" 2>&1) || rc=$?
  fi

  if [ -n "$apply_out" ]; then
    # Emit marker to stderr for visibility (grep friendly); CLI already prints
    printf '%s\n' "$apply_out" >&2
  fi

  # STRICT decision (literal "1" only). Refuse stays soft. Other outcomes soft.
  if [ "${GRKR_LINEAR_MUTATE_STRICT:-}" != "1" ]; then
    return 0
  fi

  local base
  base=$(basename "$dump_file")
  case "$base" in
    refusal.*) return 0 ;;
  esac

  # Hard-fail path: marker failed or the apply command itself exited non-zero.
  # Normalize to 1 when rc==0 but marker indicates failure (stub contract).
  if [ "$rc" -ne 0 ] || printf '%s\n' "$apply_out" | grep -q 'LINEAR_MUTATE=failed'; then
    if [ "$rc" -ne 0 ]; then
      return "$rc"
    else
      return 1
    fi
  fi

  return 0
}
