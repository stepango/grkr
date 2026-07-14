import gleeunit
import gleeunit/should
import grkr/workflow/implement_stage

pub fn main() {
  gleeunit.main()
}

pub fn generate_commit_message_test() {
  implement_stage.generate_commit_message("123", " add search index ")
  |> should.equal("feat(robot): implement #123 add search index")

  implement_stage.generate_commit_message("42", "fix bug")
  |> should.equal("feat(robot): implement #42 fix bug")

  // empty title edge
  implement_stage.generate_commit_message("99", "   ")
  |> should.equal("feat(robot): implement #99 ")
}

pub fn generate_linear_commit_message_test() {
  implement_stage.generate_linear_commit_message("ENG-123", " add search index ")
  |> should.equal("feat(robot): implement ENG-123 add search index")

  implement_stage.generate_linear_commit_message("ENG-42", "fix bug")
  |> should.equal("feat(robot): implement ENG-42 fix bug")

  // empty title edge
  implement_stage.generate_linear_commit_message("ENG-99", "   ")
  |> should.equal("feat(robot): implement ENG-99 ")
}
