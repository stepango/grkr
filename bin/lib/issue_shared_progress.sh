# bin/lib/issue_shared_progress.sh
# Concern-split slice 2 (docs/design-issue-shared-concern-split.md):
# run_progress_cli + checkpoint_marker extracted from issue_shared.sh.
# Facade (issue_shared.sh) sources this sibling; bin/grkr still sources only the facade.
# Ambient call-time deps: SCRIPT_DIR, optional GRKR_GLEAM_PROJECT_ROOT (from bin/grkr).
# run_progress_cli prefers gleam run -m grkr/progress/cli when gleam.toml present under
# project root (or GRKR_GLEAM_PROJECT_ROOT override); otherwise falls back to inline
# marker for "marker" subcommand or errors. checkpoint_marker is a thin convenience
# over the marker path.
# Zero behavior change; stable public names run_progress_cli + checkpoint_marker.

run_progress_cli() {
  local project_root
  project_root=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}

  if [ -f "$project_root/gleam.toml" ]; then
    (cd "$project_root" && gleam run -m grkr/progress/cli -- "$@")
    return
  fi

  case "${1:-}" in
    marker)
      printf '<!-- grkr:checkpoint stage=%s task=%s version=1 -->' "$2" "$3"
      ;;
    *)
      printf 'Missing Gleam project root for grkr progress CLI: %s\n' "$project_root" >&2
      return 1
      ;;
  esac
}

checkpoint_marker() {
  local stage=$1
  local task_slug=$2

  run_progress_cli marker "$stage" "$task_slug"
}
