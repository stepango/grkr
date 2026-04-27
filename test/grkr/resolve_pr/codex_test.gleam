import gleeunit
import gleeunit/should
import grkr/resolve_pr/codex
import grkr/resolve_pr/types

pub fn main() {
  gleeunit.main()
}

pub fn validate_resolution_test() {
  let conflict =
    types.ConflictFile(
      path: "test.gleam",
      our_content: "<<<<<<< ours\ncontent\n=======\nnew content\n>>>>>>> theirs",
      their_content: "new content",
    )

  let resolution =
    types.CodexResolution(
      resolved_content: "final resolved content",
      explanation: "Merged both changes",
    )

  let result = codex.validate_resolution(conflict, resolution)

  result
  |> should.be_ok()
}

pub fn validate_resolution_empty_test() {
  let conflict =
    types.ConflictFile(
      path: "test.gleam",
      our_content: "content",
      their_content: "new content",
    )

  let resolution =
    types.CodexResolution(resolved_content: "", explanation: "Empty")

  let result = codex.validate_resolution(conflict, resolution)

  result
  |> should.be_error()
}

pub fn validate_resolution_still_conflicted_test() {
  let conflict =
    types.ConflictFile(
      path: "test.gleam",
      our_content: "content",
      their_content: "new content",
    )

  let resolution =
    types.CodexResolution(
      resolved_content: "<<<<<<< ours\nstill conflicted\n>>>>>>> theirs",
      explanation: "Failed",
    )

  let result = codex.validate_resolution(conflict, resolution)

  result
  |> should.be_error()
}
