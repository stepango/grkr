import gleeunit
import gleeunit/should
import grkr/resolve_pr/types

pub fn main() {
  gleeunit.main()
}

pub fn pull_request_test() {
  let pr =
    types.PullRequest(
      number: 123,
      title: "Test PR",
      author: "testuser",
      head_ref: "feature/test",
      head_sha: "abc123",
      base_ref: "main",
      mergeable: False,
      conflicted: True,
      is_cross_repository: False,
    )

  pr.number
  |> should.equal(123)

  pr.title
  |> should.equal("Test PR")

  pr.conflicted
  |> should.be_true()
}

pub fn conflict_file_test() {
  let conflict =
    types.ConflictFile(
      path: "src/test.gleam",
      our_content: "our content",
      their_content: "their content",
    )

  conflict.path
  |> should.equal("src/test.gleam")
}

pub fn resolution_result_test() {
  let success =
    types.ResolutionSuccess(
      resolved_files: ["file1.gleam", "file2.gleam"],
      commit_sha: "abc123",
      pushed: True,
    )

  case success {
    types.ResolutionSuccess(files, sha, pushed) -> {
      files
      |> should.equal(["file1.gleam", "file2.gleam"])

      sha
      |> should.equal("abc123")

      pushed
      |> should.be_true()
    }
  }
}
