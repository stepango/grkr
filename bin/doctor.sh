#!/bin/bash

doctor_init() {
  export GRKR_ROOT=${GRKR_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  GRKR_CONFIG_FILE="$GRKR_ROOT/.grkr/config.sh"
}

doctor_fail() {
  echo "❌ $1"
  return 1
}

doctor_require_tool() {
  local tool=$1
  if ! command -v "$tool" >/dev/null 2>&1; then
    doctor_fail "$tool is required but not installed."
    return 1
  fi
}

doctor_validate_tools() {
  local status=0
  for tool in jq git gh timeout flock; do
    doctor_require_tool "$tool" || status=1
  done
  return "$status"
}

doctor_validate_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    doctor_fail "GitHub authentication failed. Run: gh auth login"
    return 1
  fi
}

doctor_validate_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    doctor_fail "codex is required but not installed."
    return 1
  fi

  if ! codex --help >/dev/null 2>&1; then
    doctor_fail "codex is installed but not runnable."
    return 1
  fi
}

doctor_normalize_repo_slug() {
  case $1 in
    git@github.com:*)
      printf '%s\n' "${1#git@github.com:}" | sed 's/\.git$//'
      ;;
    ssh://git@github.com/*)
      printf '%s\n' "${1#ssh://git@github.com/}" | sed 's/\.git$//'
      ;;
    https://github.com/*)
      printf '%s\n' "${1#https://github.com/}" | sed 's/\.git$//'
      ;;
    *)
      return 1
      ;;
  esac
}

doctor_validate_config() {
  if [ ! -f "$GRKR_CONFIG_FILE" ]; then
    doctor_fail "Missing config file: $GRKR_CONFIG_FILE"
    return 1
  fi

  # shellcheck disable=SC1090
  . "$GRKR_CONFIG_FILE" || {
    doctor_fail "Unable to load config file: $GRKR_CONFIG_FILE"
    return 1
  }

  IN_PROGRESS_VALUE=${IN_PROGRESS_VALUE:-"In Progress"}
  DONE_VALUE=${DONE_VALUE:-"Done"}
  TEST_COMMAND=${TEST_COMMAND:-"npm test"}
  BUILD_COMMAND=${BUILD_COMMAND:-""}

  local required_vars="REPO PROJECT_OWNER PROJECT_NUMBER STATUS_FIELD_NAME TODO_VALUE BACKLOG_VALUE PRIORITY_FIELD_NAME"
  local var
  local status=0
  for var in $required_vars; do
    if [ -z "${!var}" ]; then
      doctor_fail "Missing required config value: $var"
      status=1
    fi
  done
  return "$status"
}

doctor_write_default_config() {
  local project_number=$1
  local remote_url
  local remote_slug
  local project_owner
  local config_dir

  if [ -z "$project_number" ]; then
    doctor_fail "PROJECT_NUMBER is required to create $GRKR_CONFIG_FILE."
    return 1
  fi

  remote_url=$(git remote get-url origin 2>/dev/null) || {
    doctor_fail "Unable to read git remote origin."
    return 1
  }

  remote_slug=$(doctor_normalize_repo_slug "$remote_url") || {
    doctor_fail "Unsupported origin remote URL: $remote_url"
    return 1
  }

  project_owner=${remote_slug%%/*}
  config_dir=$(dirname "$GRKR_CONFIG_FILE")

  mkdir -p "$config_dir" || {
    doctor_fail "Unable to create $config_dir."
    return 1
  }

  cat > "$GRKR_CONFIG_FILE" <<EOF
REPO="$remote_slug"
MAIN_BRANCH="main"
PROJECT_OWNER="$project_owner"
PROJECT_NUMBER="$project_number"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
IN_PROGRESS_VALUE="In Progress"
DONE_VALUE="Done"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
TEST_COMMAND="npm test"
BUILD_COMMAND=""
LOOP_INTERVAL_SECS="20"
EOF
}

doctor_create_config() {
  local project_number=$1

  if [ -f "$GRKR_CONFIG_FILE" ]; then
    doctor_fail "Config file already exists: $GRKR_CONFIG_FILE"
    return 1
  fi

  doctor_write_default_config "$project_number"
}

doctor_validate_repo_remote() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null) || {
    doctor_fail "Unable to read git remote origin."
    return 1
  }

  local remote_slug
  remote_slug=$(doctor_normalize_repo_slug "$remote_url") || {
    doctor_fail "Unsupported origin remote URL: $remote_url"
    return 1
  }

  local expected_repo=$REPO
  local normalized_repo
  if normalized_repo=$(doctor_normalize_repo_slug "$REPO" 2>/dev/null); then
    expected_repo=$normalized_repo
  fi

  if [ "$remote_slug" != "$expected_repo" ]; then
    doctor_fail "Origin remote $remote_slug does not match configured repo $expected_repo."
    return 1
  fi
}

doctor_validate_grkr_dir() {
  local grkr_dir="$GRKR_ROOT/.grkr"
  local probe_dir

  mkdir -p "$grkr_dir" || {
    doctor_fail "Unable to create $grkr_dir."
    return 1
  }

  probe_dir=$(mktemp -d "$grkr_dir/.doctor.XXXXXX" 2>/dev/null) || {
    doctor_fail "Unable to write to $grkr_dir."
    return 1
  }

  rmdir "$probe_dir" 2>/dev/null || true
}

doctor_validate() {
  doctor_init

  local status=0
  doctor_validate_tools || status=1
  doctor_validate_gh_auth || status=1
  doctor_validate_codex || status=1

  if [ -f "$GRKR_CONFIG_FILE" ]; then
    doctor_validate_config || status=1
    doctor_validate_repo_remote || status=1
  else
    doctor_fail "Missing config file: $GRKR_CONFIG_FILE"
    status=1
  fi

  doctor_validate_grkr_dir || status=1

  if [ "$status" -eq 0 ]; then
    echo "✅ Startup validation passed."
  fi

  return "$status"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  doctor_validate
fi
