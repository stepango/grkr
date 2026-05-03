import grkr/linear/e2e
import grkr/linear/types
import gleeunit
import gleeunit/should
import gleam/string

pub fn main() {
  gleeunit.main()
}

pub fn format_test_result_success_test() {
  let viewer = types.LinearUser(
    id: "user-123",
    name: "Test User",
    email: "test@example.com",
  )

  let projects = []

  let teams = []

  let result = types.E2ETestSuccess(viewer, projects, teams)

  let formatted = e2e.format_test_result(result)

  formatted
  |> string.contains("E2E Tests Passed")
  |> should.be_true

  formatted
  |> string.contains("Test User")
  |> should.be_true

  formatted
  |> string.contains("test@example.com")
  |> should.be_true
}

pub fn format_test_result_blocked_test() {
  let result = types.E2ETestBlocked("No token available")

  let formatted = e2e.format_test_result(result)

  formatted
  |> string.contains("E2E Tests Blocked")
  |> should.be_true

  formatted
  |> string.contains("No token available")
  |> should.be_true
}

pub fn format_test_result_failed_test() {
  let result = types.E2ETestFailed("Connection error")

  let formatted = e2e.format_test_result(result)

  formatted
  |> string.contains("E2E Tests Failed")
  |> should.be_true

  formatted
  |> string.contains("Connection error")
  |> should.be_true
}

pub fn should_exit_success_for_success_test() {
  let viewer = types.LinearUser(
    id: "user-123",
    name: "Test User",
    email: "test@example.com",
  )

  let result = types.E2ETestSuccess(viewer, [], [])

  e2e.should_exit_success(result)
  |> should.be_true
}

pub fn should_exit_success_for_blocked_test() {
  let result = types.E2ETestBlocked("No token")

  e2e.should_exit_success(result)
  |> should.be_true
}

pub fn should_exit_success_for_failed_test() {
  let result = types.E2ETestFailed("Error")

  e2e.should_exit_success(result)
  |> should.be_false
}
