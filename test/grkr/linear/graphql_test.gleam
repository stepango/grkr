import gleam/dict
import gleam/string
import gleeunit
import gleeunit/should
import grkr/linear/graphql

pub fn main() {
  gleeunit.main()
}

pub fn viewer_query_test() {
  let query = graphql.viewer_query()

  query.query
  |> string.contains("query Viewer")
  |> should.be_true

  query.query
  |> string.contains("viewer")
  |> should.be_true

  query.variables
  |> dict.size
  |> should.equal(0)
}

pub fn projects_query_test() {
  let query = graphql.projects_query()

  query.query
  |> string.contains("query Projects")
  |> should.be_true

  query.query
  |> string.contains("projects")
  |> should.be_true
}

pub fn teams_query_test() {
  let query = graphql.teams_query()

  query.query
  |> string.contains("query Teams")
  |> should.be_true

  query.query
  |> string.contains("teams")
  |> should.be_true
}

pub fn issue_query_test() {
  let query = graphql.issue_query("test-issue-id")

  query.query
  |> string.contains("query Issue")
  |> should.be_true

  query.query
  |> string.contains("$id: String!")
  |> should.be_true

  query.variables
  |> dict.get("id")
  |> should.equal(Ok("test-issue-id"))
}

pub fn create_issue_mutation_test() {
  let query =
    graphql.create_issue_mutation("team-123", "Test Issue", "Test Description")

  query.query
  |> string.contains("mutation CreateIssue")
  |> should.be_true

  query.query
  |> string.contains("$teamId: String!")
  |> should.be_true

  query.query
  |> string.contains("success")
  |> should.be_true

  query.variables
  |> dict.get("teamId")
  |> should.equal(Ok("team-123"))

  query.variables
  |> dict.get("title")
  |> should.equal(Ok("Test Issue"))

  query.variables
  |> dict.get("description")
  |> should.equal(Ok("Test Description"))
}

pub fn create_comment_mutation_test() {
  let query = graphql.create_comment_mutation("issue-123", "Test comment body")

  query.query
  |> string.contains("mutation CreateComment")
  |> should.be_true

  query.query
  |> string.contains("$issueId: String!")
  |> should.be_true

  query.query
  |> string.contains("success")
  |> should.be_true

  query.variables
  |> dict.get("issueId")
  |> should.equal(Ok("issue-123"))

  query.variables
  |> dict.get("body")
  |> should.equal(Ok("Test comment body"))
}

pub fn update_issue_state_mutation_test() {
  let query = graphql.update_issue_state_mutation("issue-123", "state-456")

  query.query
  |> string.contains("mutation UpdateIssueState")
  |> should.be_true

  query.variables
  |> dict.get("issueId")
  |> should.equal(Ok("issue-123"))

  query.variables
  |> dict.get("stateId")
  |> should.equal(Ok("state-456"))
}

pub fn archive_issue_mutation_test() {
  let query = graphql.archive_issue_mutation("issue-123")

  query.query
  |> string.contains("mutation ArchiveIssue")
  |> should.be_true

  query.variables
  |> dict.get("issueId")
  |> should.equal(Ok("issue-123"))
}

pub fn is_query_safe_for_query_test() {
  let query = graphql.viewer_query()

  graphql.is_query_safe(query)
  |> should.be_true
}

pub fn is_query_safe_for_mutation_test() {
  let query = graphql.create_issue_mutation("team-123", "Test", "Description")

  graphql.is_query_safe(query)
  |> should.be_false
}
