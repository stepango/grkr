import gleam/dict
import gleam/string
import gleeunit
import gleeunit/should
import grkr/linear/graphql

pub fn main() {
  gleeunit.main()
}

/// Test-only binding to the FFI helper that proves Dict -> plain object encoding.
/// We stringify for easy deterministic assertions in Gleam.
@external(javascript, "./client_ffi.mjs", "variablesToJson")
fn variables_to_json(variables: dict.Dict(String, String)) -> String

pub fn variables_empty_encodes_to_empty_object_test() {
  let query = graphql.viewer_query()

  variables_to_json(query.variables)
  |> should.equal("{}")
}

pub fn variables_empty_dict_direct_test() {
  let empty = dict.new()

  variables_to_json(empty)
  |> should.equal("{}")
}

pub fn variables_single_entry_encodes_test() {
  let vars = dict.from_list([#("id", "issue-xyz")])

  variables_to_json(vars)
  |> should.equal("{\"id\":\"issue-xyz\"}")
}

pub fn variables_multiple_entries_encodes_test() {
  let vars =
    dict.from_list([
      #("teamId", "team-123"),
      #("title", "Hello"),
      #("description", "World"),
    ])

  let vars_json = variables_to_json(vars)
  // Order not guaranteed by dict, check for all key/value pairs present
  vars_json
  |> string.contains("\"teamId\":\"team-123\"")
  |> should.be_true
  vars_json
  |> string.contains("\"title\":\"Hello\"")
  |> should.be_true
  vars_json
  |> string.contains("\"description\":\"World\"")
  |> should.be_true
  // At least 3 entries worth of content
  { string.length(vars_json) > 40 }
  |> should.be_true
}

pub fn variables_nonempty_from_graphql_mutation_test() {
  let query =
    graphql.create_issue_mutation("T1", "Title here", "Desc here")

  let vars_json = variables_to_json(query.variables)
  vars_json
  |> string.contains("\"teamId\":\"T1\"")
  |> should.be_true
  vars_json
  |> string.contains("\"title\":\"Title here\"")
  |> should.be_true
}
