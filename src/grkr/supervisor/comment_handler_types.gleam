//// comment_handler_types.gleam
//// Shared types for the supervisor/comment_handler (LOC hygiene).
//// Zero behavior change; moved from monolithic comment_handler.gleam.
/// Keep "comment_handler" identity in logs/usage (distinct from workflow/handle_comment).

pub type CommentContext {
  CommentContext(
    id: String,
    raw_cmd: String,
    user_login: String,
    html_url: String,
    issue_number: String,
    issue_title: String,
    issue_body: String,
    is_pr: Bool,
    issue_state: String,
    recent_comments_json: String,
    repo: String,
  )
}

pub type WorktreeInfo {
  WorktreeInfo(dir: String, branch: String)
}
