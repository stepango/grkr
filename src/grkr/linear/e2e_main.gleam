import gleam/io
import gleam/javascript/promise.{type Promise}
import grkr/linear/e2e
import grkr/linear/types

pub fn main() -> Promise(Nil) {
  e2e.run_e2e(Nil)
  |> promise.map(fn(result) {
    io.println(e2e.format_test_result(result))

    case result {
      types.E2ETestSuccess(_, _, _, _) -> exit(0)
      types.E2ETestBlocked(_) -> exit(2)
      types.E2ETestFailed(_) -> exit(1)
    }
  })
}

@external(javascript, "../linear/e2e_ffi.mjs", "exit")
fn exit(code: Int) -> Nil
