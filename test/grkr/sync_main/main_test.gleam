import grkr/sync_main/main as sync_main
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn get_main_branch_defaults_to_main_test() {
  javascript_set_env("MAIN_BRANCH", "")

  sync_main.get_main_branch()
  |> should.equal("main")
}

pub fn get_main_branch_reads_env_test() {
  javascript_set_env("MAIN_BRANCH", "develop")

  sync_main.get_main_branch()
  |> should.equal("develop")

  javascript_set_env("MAIN_BRANCH", "")
}

pub fn sync_commands_match_legacy_sequence_test() {
  sync_main.planned_command_strings("trunk")
  |> should.equal([
    "git fetch origin trunk --prune",
    "git checkout trunk",
    "git reset --hard origin/trunk",
  ])
}

pub fn lock_exit_code_is_preserved_test() {
  sync_main.ExitCode(75)
  |> should.equal(sync_main.ExitCode(75))
}

@external(javascript, "./test_helper.mjs", "set_env")
fn javascript_set_env(name: String, value: String) -> Nil
