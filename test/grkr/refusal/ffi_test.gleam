import gleam/list
import gleeunit
import gleeunit/should
import grkr/refusal/ffi

pub fn main() {
  gleeunit.main()
}

pub fn parse_json_test() {
  case ffi.parse("{\"title\": \"Test Issue\", \"number\": 42}") {
    Ok(v) -> {
      ffi.get_field_path_string(v, ["title"]) |> should.equal("Test Issue")
      ffi.get_field_path_string(v, ["number"]) |> should.equal("42")
    }
    Error(_) -> should.fail()
  }

  ffi.parse("not json") |> should.be_error()
}

pub fn get_field_path_test() {
  let json = "{\"data\": {\"items\": [{\"id\": \"PVTI_1\", \"status\": {\"name\": \"Todo\"}}]}}"
  case ffi.parse(json) {
    Ok(v) -> {
      ffi.get_field_path_string(v, ["data", "items", "0", "id"]) |> should.equal("PVTI_1")
      ffi.get_field_path_string(v, ["data", "items", "0", "status", "name"]) |> should.equal("Todo")
      ffi.get_field_path_string(v, ["missing", "path"]) |> should.equal("")
    }
    Error(_) -> should.fail()
  }
}

pub fn decode_array_test() {
  let json = "{\"comments\": [{\"id\": \"C1\", \"body\": \"first\"}, {\"id\": \"C2\", \"body\": \"second\"}]}"
  case ffi.parse(json) {
    Ok(v) -> {
      let comments = ffi.get_field_path(v, ["comments"])
      case ffi.decode_array(comments) {
        Ok(arr) -> list.length(arr) |> should.equal(2)
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn exec_result_test() {
  // exec a safe non-gh command to cover the FFI path and ExecResult shape
  let res = ffi.execute_command("echo", ["-n", "hello from ffi test"])
  res.exit_code |> should.equal(0)
  res.stdout |> should.equal("hello from ffi test")
}

pub fn exists_file_test() {
  ffi.exists_file("test/grkr/refusal/ffi_test.gleam") |> should.be_true()
  ffi.exists_file("/nonexistent/path/that/does/not/exist") |> should.be_false()
}
