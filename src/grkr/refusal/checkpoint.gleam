import gleam/option.{type Option, None, Some}
import grkr/refusal/types.{type RefusalClass, type RefusalConfig, type RefusalError, OtherError}

/// Stub module to unblock Gleam build for supervisor/recovery work.
/// Full port of ensure_refusal_checkpoint + fetch from bin/worker-refuse-issue.sh
/// and bin/grkr-issue-workflow.sh will be in a dedicated refusal checkpoint card later.
/// (GitHub-only v2 slice)

pub type RefusalCheckpoint {
  RefusalCheckpoint(
    comment_id: Option(String),
  )
}

/// Returns the full issue JSON from `gh issue view $num --comments --json title,body,url,number,projectItems,comments`
/// or similar. Currently stubbed to allow supervisor build to succeed.
pub fn fetch_issue_json(repo: String, issue_number: Int) -> Result(String, String) {
  Error("not_implemented_in_gleam_checkpoint: fetch_issue_json stub - call via FFI gh or use shell worker-refuse-issue.sh for now")
}

/// Idempotent ensure: writes refusal.md, posts GH comment exactly once, returns the comment_id.
/// Stub returns error; see shell impl at bin/worker-refuse-issue.sh:253 for full logic.
pub fn ensure_refusal_checkpoint(
  cfg: RefusalConfig,
  issue_number: Int,
  issue_json: String,
  task_slug: String,
  title: String,
  class: RefusalClass,
  reasoning: String,
) -> Result(RefusalCheckpoint, RefusalError) {
  Error(OtherError("not_implemented_in_gleam_checkpoint: ensure_refusal_checkpoint stub"))
}
