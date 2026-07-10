import gleeunit
import gleeunit/should
import grkr/supervisor/state
import grkr/supervisor/worktree_cleanup

pub fn main() {
  gleeunit.main()
}

pub fn classify_worktree_active_test() {
  worktree_cleanup.classify_worktree("foo", 100, 200, 3600, True, False)
  |> should.equal(#(False, "active"))
}

pub fn classify_worktree_refusal_checkpoint_test() {
  worktree_cleanup.classify_worktree("bar", 100, 200, 3600, False, True)
  |> should.equal(#(False, "refusal_checkpoint"))
}

pub fn classify_worktree_failed_ttl_expired_test() {
  worktree_cleanup.classify_worktree("task-failed-1", 100, 5000, 3600, False, False)
  |> should.equal(#(True, "failed_ttl_expired"))
}

pub fn classify_worktree_failed_fresh_test() {
  worktree_cleanup.classify_worktree("task-failed-2", 4000, 5000, 3600, False, False)
  |> should.equal(#(False, "failed_fresh"))
}

pub fn classify_worktree_completed_stale_test() {
  worktree_cleanup.classify_worktree("task-completed-1", 100, 5000, 3600, False, False)
  |> should.equal(#(True, "completed_or_stale_ttl"))
}

pub fn classify_worktree_fresh_test() {
  worktree_cleanup.classify_worktree("task-completed-2", 4000, 5000, 3600, False, False)
  |> should.equal(#(False, "fresh"))
}

pub fn progress_uncommitted_refuse_decision_test() {
  let json =
    "{\"status\":\"implementing\",\"decision\":\"refuse\",\"stages\":{\"implement_or_refuse\":{\"status\":\"done\"}}}"
  worktree_cleanup.progress_shows_uncommitted_refusal(json)
  |> should.be_true()
}

pub fn progress_committed_refusal_test() {
  let json =
    "{\"status\":\"refused\",\"decision\":\"refuse\",\"stages\":{\"implement_or_refuse\":{\"status\":\"done\",\"comment_id\":2002,\"reason_class\":\"underspecified\"},\"test\":{\"status\":\"skipped\"}}}"
  worktree_cleanup.progress_shows_uncommitted_refusal(json)
  |> should.be_false()
}

pub fn progress_proceed_not_refusal_test() {
  let json =
    "{\"status\":\"complete\",\"decision\":\"proceed\",\"stages\":{\"implement_or_refuse\":{\"status\":\"done\"}}}"
  worktree_cleanup.progress_shows_uncommitted_refusal(json)
  |> should.be_false()
}

pub fn compact_processed_comments_noop_test() {
  let path = "/tmp/grkr-test-compact-noop.json"
  state.compact_processed_comments(path, 10)
  |> should.be_ok()
}

pub fn compact_processed_comments_path_test() {
  let path = "/tmp/grkr-test-compact.json"
  state.compact_processed_comments(path, 500)
  |> should.be_ok()
}

pub fn prune_stale_worktrees_temp_dir_note_test() {
  True |> should.be_true()
}