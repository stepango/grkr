## 24. Detailed issue workflow pseudocode

```bash
worker-exec-issue.sh() {
  load_issue_context "$ISSUE_NUMBER"
  create_or_attach_worktree "$TASK_SLUG"

  ensure_research_checkpoint
  ensure_plan_checkpoint

  decision=$(decide_implement_or_refuse)

  if [ "$decision" = "refuse" ]; then
    worker-refuse-issue.sh "$ISSUE_NUMBER" "$PROJECT_ITEM_ID" "$TASK_SLUG"
    mark_issue_workflow_refused
    cleanup_issue_worktree
    return 0
  fi

  run_implementation || {
    if should_convert_failure_to_refusal; then
      worker-refuse-issue.sh "$ISSUE_NUMBER" "$PROJECT_ITEM_ID" "$TASK_SLUG"
      mark_issue_workflow_refused
      cleanup_issue_worktree
      return 0
    fi
    mark_issue_workflow_failed
    cleanup_issue_worktree
    return 1
  }

  ensure_test_checkpoint
  mark_issue_workflow_complete
  cleanup_issue_worktree
}
```

Refusal worker example:

```bash
worker-refuse-issue.sh() {
  local issue_number="$1"
  local project_item_id="$2"
  local task_slug="$3"

  generate_refusal_md "$issue_number" "$task_slug"
  post_refusal_comment_if_missing "$issue_number" "$task_slug"
  move_project_item_to_backlog "$project_item_id"
  update_progress_refused "$issue_number" "$task_slug"
}
```

---

