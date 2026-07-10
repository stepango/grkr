import gleam/option
import gleeunit
import gleeunit/should
import grkr/refusal/checkpoint

pub fn main() {
  gleeunit.main()
}

pub fn refusal_checkpoint_type_test() {
  // basic type smoke test
  let _ = checkpoint.RefusalCheckpoint(comment_id: option.None)
  should.equal(1, 1)
}
