import grkr/supervisor/types
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn job_key_roundtrip_test() {
  let key = types.job_key_from_string("issue:42:execution")
  case key {
    Ok(k) -> {
      types.job_key_to_string(k) |> should.equal("issue:42:execution")
      types.job_key_lock_name(k) |> should.equal("issue-42")
      types.job_key_log_basename(k) |> should.equal("issue-42-execution")
    }
    Error(_) -> should.fail()
  }

  let pr_key = types.job_key_from_string("pr:123:conflict-resolution")
  case pr_key {
    Ok(k) -> {
      types.job_key_to_string(k) |> should.equal("pr:123:conflict-resolution")
      types.job_key_lock_name(k) |> should.equal("pr-123")
      types.job_key_log_basename(k) |> should.equal("pr-123-conflict-resolution")
    }
    Error(_) -> should.fail()
  }
}

pub fn job_key_invalid_test() {
  types.job_key_from_string("foo:bar")
  |> should.equal(Error("unknown job key format: foo:bar"))
}

pub fn phase_to_string_test() {
  types.phase_to_string(types.SyncMain) |> should.equal("sync_main")
  types.phase_to_string(types.PickAndScheduleIssueExecution)
  |> should.equal("pick_and_schedule_issue_execution")
  types.phase_to_string(types.Supervisor) |> should.equal("supervisor")
}

pub fn supervisor_error_to_string_test() {
  types.supervisor_error_to_string(types.MissingRequiredEnv("REPO"))
  |> should.equal("missing_required_env:REPO")

  types.supervisor_error_to_string(types.InvalidPhaseName("foo"))
  |> should.equal("invalid phase name: foo")
}

pub fn pick_phase_integration_note_test() {
  // Pick phase calls grkr/supervisor/pick.pick_next (GRKR_ISSUE_PROVIDER dispatch).
  // Fixture tests: test/grkr/supervisor/pick_test.gleam (GITHUB_FIXTURE_PATH + LINEAR_FIXTURE_PATH).
  // E2E: GRKR_MAX_TICKS=1 GITHUB_FIXTURE_PATH=... gleam run -m grkr/supervisor/main
  True |> should.be_true()
}

