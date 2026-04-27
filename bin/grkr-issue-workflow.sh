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
  local worktree_dir
  local base_ref

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
    base_ref=$(issue_worktree_base_ref)
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
    | if $decision == "proceed" then
        .stages.implement_or_refuse.status = "done"
        | .status = "implementing"
      else
        .
      end
  ' "$progress_file" > "$tmp_file"
  mv "$tmp_file" "$progress_file"
}

valid_refusal_class() {
  case "$1" in
    underspecified|too_large|missing_dependency|needs_design_decision|unsafe_autonomous_change|repo_not_ready|other)
      return 0
      ;;
  esac
  return 1
}

normalize_refusal_class_candidate() {
  local candidate

  candidate=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr ' -' '__' | tr -cd 'a-z0-9_')
  if valid_refusal_class "$candidate"; then
    printf '%s\n' "$candidate"
  else
    printf 'other\n'
  fi
}

refusal_requires_backlog_move() {
  case "${ENABLE_PROJECT_STATUS_UPDATES:-true}" in
    false|False|FALSE|0|no|No|NO)
      return 1
      ;;
  esac

  case "${REFUSAL_REQUIRES_BACKLOG_MOVE:-true}" in
    false|False|FALSE|0|no|No|NO)
      return 1
      ;;
  esac

  return 0
}

extract_decision_from_output() {
  local output_file=$1

  awk '
    {
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      lower=tolower(line)
      if (lower == "proceed" || lower == "refuse") {
        decision=lower
      }
    }
    END {
      if (decision != "") {
        print decision
      }
    }
  ' "$output_file"
}

parse_refusal_decision_output() {
  local output_file=$1

  awk '
    {
      trimmed=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)
      lower=tolower(trimmed)
      lines[++count]=$0
      if (lower == "refuse") {
        refusal_line=count
      }
    }
    END {
      if (!refusal_line) {
        exit 0
      }

      class_line=""
      explanation=""
      seen_class=0
      for (i = refusal_line + 1; i <= count; i++) {
        line=lines[i]
        trimmed=line
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)
        if (trimmed == "") {
          continue
        }

        if (!seen_class) {
          class_line=trimmed
          seen_class=1
          continue
        }

        if (explanation != "") {
          explanation=explanation "\n"
        }
        explanation=explanation trimmed
      }

      if (class_line != "") {
        print class_line
      }
      print "---"
      if (explanation != "") {
        print explanation
      }
    }
  ' "$output_file"
}

refusal_missing_requirements_markdown() {
  local refusal_class=$1
  local reasoning=$2

  case "$refusal_class" in
    underspecified)
      cat <<EOF
- Explicit acceptance criteria or expected behavior examples
- Clear success conditions for the implementation and test stages
EOF
      ;;
    too_large)
      cat <<EOF
- A smaller, explicitly scoped first slice of work
- A concrete split between independent follow-up issues
EOF
      ;;
    missing_dependency)
      cat <<EOF
- The missing upstream dependency, API, or prerequisite issue
- Confirmation that the dependency is available in the target branch
EOF
      ;;
    needs_design_decision)
      cat <<EOF
- A concrete design or product decision for the ambiguous behavior
- Confirmation of the preferred implementation direction
EOF
      ;;
    unsafe_autonomous_change)
      cat <<EOF
- Human review for the risky change path
- A safer bounded approach or rollback strategy
EOF
      ;;
    repo_not_ready)
      cat <<EOF
- Repository health restored enough for issue-local changes to be validated
- Confirmation that unrelated build or test failures are resolved
EOF
      ;;
    *)
      cat <<EOF
- The missing prerequisite identified in the refusal reasoning above
- A narrower, directly testable issue scope
EOF
      ;;
  esac
}

refusal_next_steps_markdown() {
  local refusal_class=$1

  case "$refusal_class" in
    too_large)
      cat <<EOF
- Split the issue into smaller independently testable tasks
- Re-run the workflow against the first bounded slice
EOF
      ;;
    *)
      cat <<EOF
- Update the issue with the missing detail identified above
- Re-run the workflow after the issue is clarified and bounded
EOF
      ;;
  esac
}

refusal_split_recommendation() {
  case "$1" in
    too_large|unsafe_autonomous_change)
      printf 'Yes. The current issue is too broad for one safe autonomous change.\n'
      ;;
    *)
      printf 'No immediate split is required if the missing prerequisite can be resolved directly in this issue.\n'
      ;;
  esac
}

refusal_follow_up_recommendation() {
  case "$1" in
    too_large|missing_dependency|needs_design_decision)
      printf 'Yes. Follow-up issues are recommended to separate prerequisite or decision work.\n'
      ;;
    *)
      printf 'Not necessarily. The current issue may proceed once the missing information is added.\n'
      ;;
  esac
}

write_refusal_checkpoint_file() {
  local checkpoint_file=$1
  local issue=$2
  local title=$3
  local task_slug=$4
  local refusal_class=$5
  local reasoning=$6

  {
    printf '%s\n\n' "$(checkpoint_marker refusal "$task_slug")"
    printf '## Implementation refused\n\n'
    printf 'Issue #%s: %s\n\n' "$issue" "$title"
    printf '### Refusal summary\n\n'
    printf 'The issue was not implemented because the decision gate returned `refuse`.\n\n'
    printf '### Reason class\n\n'
    printf '%s\n\n' "$refusal_class"
    printf '### Detailed reasoning\n\n'
    printf '%s\n\n' "$reasoning"
    printf '### What is needed before implementation\n\n'
    refusal_missing_requirements_markdown "$refusal_class" "$reasoning"
    printf '\n\n### Suggested next actions\n\n'
    refusal_next_steps_markdown "$refusal_class"
    printf '\n\n### Should the issue be split?\n\n'
    refusal_split_recommendation "$refusal_class"
    printf '\n### Are follow-up issues recommended?\n\n'
    refusal_follow_up_recommendation "$refusal_class"
  } > "$checkpoint_file"
}

ensure_refusal_checkpoint() {
  local issue=$1
  local issue_json=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local progress_file=$6
  local refusal_class=$7
  local reasoning=$8
  local checkpoint_file
  local comment_id
  local comment_body
  local refreshed_comments_json

  checkpoint_file="$task_dir/refusal.md"
  comment_id=$(checkpoint_comment_id_from_json "$issue_json" refusal "$task_slug")

  if [ -f "$checkpoint_file" ] && [ -n "$comment_id" ]; then
    echo "♻️ Reusing refusal checkpoint for issue #$issue from comment $comment_id." >&2
    printf '%s\n' "$comment_id"
    return 0
  fi

  if [ -n "$comment_id" ] && [ ! -f "$checkpoint_file" ]; then
    comment_body=$(checkpoint_comment_body_from_json "$issue_json" refusal "$task_slug")
    if [ -n "$comment_body" ]; then
      printf '%s\n' "$comment_body" > "$checkpoint_file"
      echo "♻️ Restored refusal checkpoint for issue #$issue from comment $comment_id." >&2
      printf '%s\n' "$comment_id"
      return 0
    fi
  fi

  write_refusal_checkpoint_file "$checkpoint_file" "$issue" "$title" "$task_slug" "$refusal_class" "$reasoning"
  echo "📝 Posting refusal checkpoint for issue #$issue..." >&2
  gh issue comment "$issue" --body-file "$checkpoint_file" >/dev/null
  refreshed_comments_json=$(fetch_issue_comments_json "$issue")
  comment_id=$(checkpoint_comment_id_from_json "$refreshed_comments_json" refusal "$task_slug")
  printf '%s\n' "$comment_id"
}

cleanup_issue_worktree() {
  local worktree_dir=$1

  [ -n "$worktree_dir" ] || return 0
  [ -e "$worktree_dir" ] || return 0

  if git worktree remove --force "$worktree_dir" >/dev/null 2>&1; then
    echo "🧹 Removed issue worktree: $worktree_dir" >&2
    return 0
  fi

  return 1
}

complete_issue_refusal() {
  local issue=$1
  local issue_json=$2
  local task_slug=$3
  local task_dir=$4
  local title=$5
  local progress_file=$6
  local decision_output_file=$7
  local worktree_dir=$8
  local explicit_refusal_class=${9:-}
  local explicit_reasoning=${10:-}
  local parsed_refusal
  local refusal_class_candidate
  local refusal_class
  local reasoning
  local refusal_comment_id

  if [ -n "$explicit_refusal_class" ]; then
    refusal_class=$(normalize_refusal_class_candidate "$explicit_refusal_class")
    reasoning="$explicit_reasoning"
    if [ -z "$reasoning" ]; then
      reasoning="The issue does not appear ready for safe autonomous implementation in its current state."
    fi
  else
    parsed_refusal=$(parse_refusal_decision_output "$decision_output_file")
    refusal_class_candidate=$(printf '%s\n' "$parsed_refusal" | awk 'NR == 1 {print}')
    refusal_class=$(normalize_refusal_class_candidate "$refusal_class_candidate")
    reasoning=$(printf '%s\n' "$parsed_refusal" | awk 'found {print} /^---$/ {found=1}' | sed '/^$/d')
    if [ -z "$reasoning" ]; then
      reasoning="The issue does not appear ready for safe autonomous implementation in its current state."
    fi
  fi

  refusal_comment_id=$(ensure_refusal_checkpoint "$issue" "$issue_json" "$task_slug" "$task_dir" "$title" "$progress_file" "$refusal_class" "$reasoning")
  if refusal_requires_backlog_move; then
    if ! move_issue_to_backlog "$issue" "$issue_json" >&2; then
      echo "⚠️ Refusal for issue #$issue was recorded, but the project status could not be moved to ${BACKLOG_VALUE:-Backlog}." >&2
    fi
  fi
  cleanup_issue_worktree "$worktree_dir" || true
  printf '%s\n' "$refusal_class"
  printf '%s\n' "$refusal_comment_id"
}

run_implementation_decision_gate() {
  local issue=$1
  local progress_file=$2
  local prompt_file=$3
  local output_file=$4
  local worktree_dir=$5
  local decision

  run_codex_prompt "$prompt_file" "$output_file" "decide whether to implement the issue" replace "$worktree_dir"
  decision=$(extract_decision_from_output "$output_file")

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

detect_implementation_refusal() {
  local output_file=$1

  awk '
    BEGIN {
      found_refuse = 0
      refusal_class = ""
      in_reasoning = 0
      reasoning = ""
    }
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      lower = tolower(line)

      if (lower ~ /^refuse(:|[^a-z]|$)/) {
        found_refuse = 1
        next
      }

      if (found_refuse && refusal_class == "") {
        if (line ~ /^(underspecified|too_large|missing_dependency|needs_design_decision|unsafe_autonomous_change|repo_not_ready|other)$/) {
          refusal_class = line
          in_reasoning = 1
          next
        }
      }

      if (in_reasoning && line != "") {
        if (reasoning != "") {
          reasoning = reasoning "\n"
        }
        reasoning = reasoning line
      }
    }
    END {
      if (found_refuse) {
        if (refusal_class == "") {
          refusal_class = "other"
        }
        print refusal_class
        print "---"
        if (reasoning != "") {
          print reasoning
        } else {
          print "Implementation discovered that the issue is not ready for safe autonomous completion."
        }
      }
    }
  ' "$output_file"
}
