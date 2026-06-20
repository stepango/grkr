import gleam/option
import gleeunit
import gleeunit/should
import grkr/supervisor/ffi
import grkr/supervisor/recovery

pub fn main() {
  gleeunit.main()
}

pub fn stale_purge_reason_ttl_test() {
  recovery.stale_purge_reason(90_001, 86_400, False)
  |> should.equal(option.Some("stale_ttl"))
}

pub fn stale_purge_reason_ttl_prefers_over_hung_test() {
  recovery.stale_purge_reason(90_000, 86_400, True)
  |> should.equal(option.Some("stale_ttl"))
}

pub fn stale_purge_reason_hung_lock_grace_test() {
  recovery.stale_purge_reason(299, 86_400, True)
  |> should.equal(option.None)
  recovery.stale_purge_reason(300, 86_400, True)
  |> should.equal(option.Some("stale_hung_lock"))
}

pub fn stale_purge_reason_fresh_alive_test() {
  recovery.stale_purge_reason(100, 86_400, False)
  |> should.equal(option.None)
}

pub fn active_job_age_seconds_valid_iso_test() {
  let started = "2026-01-01T00:00:00.000Z"
  let started_unix = ffi.parse_utc_iso_to_unix(started)
  case recovery.active_job_age_seconds(started, started_unix + 3600) {
    Ok(age) -> age |> should.equal(3600)
    Error(_) -> should.fail()
  }
}

pub fn active_job_age_seconds_invalid_test() {
  recovery.active_job_age_seconds("", 1_700_000_000)
  |> should.equal(Error(Nil))
  recovery.active_job_age_seconds("not-a-date", 1_700_000_000)
  |> should.equal(Error(Nil))
}

pub fn parse_utc_iso_to_unix_matches_supervisor_format_test() {
  ffi.parse_utc_iso_to_unix("2026-05-17T12:00:00Z")
  |> should.equal(ffi.parse_utc_iso_to_unix("2026-05-17T12:00:00.000Z"))
}