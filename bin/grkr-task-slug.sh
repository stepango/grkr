#!/bin/bash

run_task_slug_cli() {
  local project_root
  project_root=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}

  if [ ! -f "$project_root/gleam.toml" ]; then
    printf 'Missing Gleam project root for grkr task slug CLI: %s\n' "$project_root" >&2
    return 1
  fi

  (cd "$project_root" && gleam run -m grkr/task_slug/cli -- "$@")
}

task_slug_for_issue() {
  run_task_slug_cli task-slug "$1" "$2"
}
