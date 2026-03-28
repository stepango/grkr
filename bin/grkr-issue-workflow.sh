#!/bin/bash

git_in_issue_context() {
  if [ -n "${CURRENT_ISSUE_WORKTREE:-}" ]; then
    (
      cd "$CURRENT_ISSUE_WORKTREE" &&
      git "$@"
    )
    return
  fi

  git "$@"
}

issue_worktree_dir() {
  printf '%s\n' "$GRKR_ROOT/.grkr/worktrees/$1"
}

issue_worktree_ready() {
  local worktree_dir=$1

  [ -f "$worktree_dir/.git" ] || [ -d "$worktree_dir/.git" ]
}

issue_worktree_base_ref() {
  local main_branch=${MAIN_BRANCH:-main}

  if git show-ref --verify --quiet "refs/remotes/origin/$main_branch"; then
    printf 'origin/%s\n' "$main_branch"
  elif git show-ref --verify --quiet "refs/heads/$main_branch"; then
    printf '%s\n' "$main_branch"
  else
    printf 'HEAD\n'
  fi
}

prepare_issue_worktree() {
  local branch=$1
  local task_slug=$2
  local base_ref=${3:-}
  local worktree_dir

  worktree_dir=$(issue_worktree_dir "$task_slug")
  mkdir -p "$(dirname "$worktree_dir")"

  if issue_worktree_ready "$worktree_dir"; then
    echo "♻️ Reusing issue worktree: $worktree_dir" >&2
    printf '%s\n' "$worktree_dir"
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "⚠️ Branch $branch already exists locally. Reusing it in an issue worktree..." >&2
    git worktree add "$worktree_dir" "$branch" >/dev/null
  elif git ls-remote --heads origin "$branch" | grep -q "$branch"; then
    echo "⚠️ Branch $branch already exists remotely. Reusing it in an issue worktree..." >&2
    git worktree add -b "$branch" "$worktree_dir" "origin/$branch" >/dev/null
  else
    if [ -z "$base_ref" ]; then
      base_ref=$(issue_worktree_base_ref)
    fi
    git worktree add -b "$branch" "$worktree_dir" "$base_ref" >/dev/null
    echo "🌿 Created issue worktree for branch: $branch" >&2
  fi

  printf '%s\n' "$worktree_dir"
}

collect_relevant_issue_paths() {
  {
    git_in_issue_context diff --name-only --relative
    git_in_issue_context diff --cached --name-only --relative
    git_in_issue_context ls-files --others --exclude-standard
  } | awk 'NF && $0 !~ /^\.grkr\//' | awk '!seen[$0]++'
}

stage_relevant_issue_files() {
  local path

  if [ -z "${CURRENT_ISSUE_WORKTREE:-}" ]; then
    git add .
    return 0
  fi

  git_in_issue_context reset >/dev/null
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    git_in_issue_context add -A -- "$path"
  done < <(collect_relevant_issue_paths)
}

task_log_supports_sharding() {
  case "$1" in
    */.grkr/tasks/*/implementation.log) return 0 ;;
    *) return 1 ;;
  esac
}

task_log_parts_dir() {
  local output_file=$1

  printf '%s/codex/%s.parts\n' "$(dirname "$output_file")" "$(basename "$output_file")"
}

task_log_is_sharded() {
  local parts_dir

  parts_dir=$(task_log_parts_dir "$1")
  [ -d "$parts_dir" ] && [ -e "$parts_dir/part-0000" ]
}

emit_task_log_stream() {
  local output_file=$1
  local parts_dir
  local part

  if task_log_is_sharded "$output_file"; then
    parts_dir=$(task_log_parts_dir "$output_file")
    for part in "$parts_dir"/part-*; do
      [ -e "$part" ] || continue
      cat "$part"
    done
    return 0
  fi

  [ -f "$output_file" ] && cat "$output_file"
}

write_task_log_manifest() {
  local output_file=$1
  local total_lines=$2
  local max_lines=${MAX_FILE_LINES:-1000}
  local task_dir
  local parts_dir
  local part
  local relative_part
  local part_count=0

  task_dir=$(dirname "$output_file")
  parts_dir=$(task_log_parts_dir "$output_file")

  {
    printf '# Sharded Codex Output\n\n'
    printf 'The full transcript exceeded the repository %s-line limit, so grkr stored it in numbered parts.\n\n' "$max_lines"
    printf -- '- Stable entrypoint: `%s`\n' "$(basename "$output_file")"
    printf -- '- Total lines: %s\n' "$total_lines"
    printf -- '- Part size: up to %s lines\n' "$max_lines"
    printf '\n## Parts\n\n'
    for part in "$parts_dir"/part-*; do
      [ -e "$part" ] || continue
      part_count=$((part_count + 1))
      relative_part=${part#"$task_dir"/}
      printf -- '- `%s`\n' "$relative_part"
    done
    if [ "$part_count" -eq 0 ]; then
      printf -- '- `(no parts written)`\n'
    fi
  } > "$output_file"
}

persist_task_log_output() {
  local run_output_file=$1
  local output_file=$2
  local phase_label=$3
  local mode=${4:-replace}
  local max_lines=${MAX_FILE_LINES:-1000}
  local combined_file
  local parts_dir
  local line_count

  if ! task_log_supports_sharding "$output_file"; then
    if [ "$mode" = "append" ] && [ -f "$output_file" ]; then
      {
        printf '\n[grkr %s]\n\n' "$phase_label"
        cat "$run_output_file"
      } >> "$output_file"
      rm -f "$run_output_file"
    else
      mv "$run_output_file" "$output_file"
    fi
    return 0
  fi

  combined_file=$(mktemp "${TMPDIR:-/tmp}/grkr-task-log.XXXXXX")
  if [ "$mode" = "append" ] && { [ -f "$output_file" ] || task_log_is_sharded "$output_file"; }; then
    emit_task_log_stream "$output_file" > "$combined_file"
    {
      if [ -s "$combined_file" ]; then
        printf '\n[grkr %s]\n\n' "$phase_label"
      fi
      cat "$run_output_file"
    } >> "$combined_file"
  else
    cat "$run_output_file" > "$combined_file"
  fi

  line_count=$(wc -l < "$combined_file" | tr -d '[:space:]')
  if [ "$line_count" -le "$max_lines" ]; then
    mv "$combined_file" "$output_file"
    rm -rf "$(task_log_parts_dir "$output_file")"
    rm -f "$run_output_file"
    return 0
  fi

  parts_dir=$(task_log_parts_dir "$output_file")
  rm -rf "$parts_dir"
  mkdir -p "$parts_dir"
  split -l "$max_lines" -d -a 4 "$combined_file" "$parts_dir/part-"
  write_task_log_manifest "$output_file" "$line_count"
  rm -f "$combined_file" "$run_output_file"
}

update_task_progress_decision() {
  local progress_file=$1
  local decision=$2
  local now
  local tmp_file

  now=$(timestamp_utc)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-progress.XXXXXX")
  jq \
    --arg decision "$decision" \
    --arg updated_at "$now" '
    .decision = $decision
    | .updated_at = $updated_at
    | .stages.implement_or_refuse.status = "done"
    | if $decision == "proceed" then
        .status = "implementing"
      else
        .status = "refused"
        | .stages.test.status = "skipped"
      end
  ' "$progress_file" > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

run_implementation_decision_gate() {
  local issue=$1
  local progress_file=$2
  local prompt_file=$3
  local output_file=$4
  local worktree_dir=$5
  local decision

  run_codex_prompt "$prompt_file" "$output_file" "decide whether to implement the issue" replace "$worktree_dir"
  decision=$(grep -Eio '\b(proceed|refuse)\b' "$output_file" | head -n1 | tr '[:upper:]' '[:lower:]')

  case "$decision" in
    proceed|refuse)
      update_task_progress_decision "$progress_file" "$decision"
      IMPLEMENTATION_DECISION=$decision
      ;;
    *)
      echo "❌ Decision gate for issue #$issue returned an invalid result."
      return 1
      ;;
  esac
}
