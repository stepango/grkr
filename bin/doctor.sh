#!/bin/bash
# Thin wrapper: doctor_init stays in shell for sourced callers; validation in grkr/doctor (Gleam).
# spec/parts/08 + 10; parity with legacy doctor.sh messages and exit codes.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

doctor_init() {
  export GRKR_ROOT=${GRKR_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  export GRKR_CONFIG_FILE="${GRKR_CONFIG_FILE:-$GRKR_ROOT/.grkr/config.sh}"
}

doctor_gleam_project() {
  printf '%s\n' "${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
}

doctor_gleam() {
  local prj
  prj=$(doctor_gleam_project)
  if [ ! -f "$prj/gleam.toml" ]; then
    echo "❌ Missing gleam.toml at $prj (for grkr/doctor CLI)" >&2
    return 1
  fi
  (
    cd "$prj" || exit 1
    export GRKR_ROOT GRKR_CONFIG_FILE
    gleam run -m grkr/doctor/cli -- "$@"
  )
}

doctor_validate() {
  doctor_init
  doctor_gleam validate
}

doctor_create_config() {
  local project_number=$1
  doctor_init
  doctor_gleam create-config "$project_number"
}

# Legacy aliases for any external callers (delegate to Gleam).
doctor_write_default_config() {
  doctor_create_config "$1"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  doctor_init
  PROJECT_ROOT=$(doctor_gleam_project)
  cd "$PROJECT_ROOT" || exit 1
  export GRKR_ROOT GRKR_CONFIG_FILE
  exec gleam run -m grkr/doctor/cli -- validate
fi