import grkr/doctor/validate

@external(javascript, "../doctor/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

pub fn main() {
  case argv() {
    [] -> exit(validate.run_validate())
    ["validate"] -> exit(validate.run_validate())
    ["create-config", project_number] -> exit(validate.run_create_config(project_number))
    ["help"] | ["--help"] | ["-h"] -> {
      emit_usage()
      exit(2)
    }
    _ -> {
      emit_usage()
      exit(2)
    }
  }
}

fn emit_usage() {
  console_log("Usage: gleam run -m grkr/doctor/cli -- [validate|create-config <n>|help]")
  console_log("")
  console_log("Startup validation for grkr (GitHub-only v2). Mirrors bin/doctor.sh checks.")
}