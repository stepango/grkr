import gleam/list
import gleeunit/should
import grkr/doctor/config_parse

pub fn normalize_git_ssh_test() {
  config_parse.normalize_repo_slug("git@github.com:stepango/grkr.git")
  |> should.equal(Ok("stepango/grkr"))
}

pub fn normalize_https_test() {
  config_parse.normalize_repo_slug("https://github.com/stepango/grkr.git")
  |> should.equal(Ok("stepango/grkr"))
}

pub fn parse_config_line_test() {
  let content =
    "REPO=\"stepango/grkr\"\nPROJECT_NUMBER=\"42\"\n# comment\n"
  let keys =
    config_parse.parse_config_assignments(content)
    |> list.map(fn(pair) {
      let #(k, _) = pair
      k
    })
  should.be_true(list.contains(keys, "REPO"))
  should.be_true(list.contains(keys, "PROJECT_NUMBER"))
}

pub fn missing_required_test() {
  let assignments = [#("REPO", "o/r")]
  config_parse.missing_required_keys(assignments)
  |> should.not_equal([])
}