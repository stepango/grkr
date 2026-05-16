import gleam/list
import gleam/option
import gleeunit
import gleeunit/should
import grkr/project_status/resolution
import grkr/project_status/types.{StatusOption}

pub fn main() {
  gleeunit.main()
}

pub fn parse_project_fields_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"},{\"id\":\"O_2\",\"name\":\"In Progress\"}]}]}"

  let result = resolution.parse_project_fields(field_list_json)

  result
  |> should.be_ok()

  let assert Ok(fields) = result
  fields
  |> list.length()
  |> should.equal(1)
}

pub fn find_status_field_by_name_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"},{\"id\":\"O_2\",\"name\":\"In Progress\"}]}]}"

  let assert Ok(fields) = resolution.parse_project_fields(field_list_json)

  let result = resolution.find_status_field(fields, "Status")

  result
  |> should.be_ok()

  let assert Ok(field) = result
  field.id
  |> should.equal("F_1")

  field.name
  |> should.equal("Status")
}

pub fn find_status_field_case_insensitive_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"}]}]}"

  let assert Ok(fields) = resolution.parse_project_fields(field_list_json)

  let result = resolution.find_status_field(fields, "status")

  result
  |> should.be_ok()
}

pub fn find_status_option_by_name_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"},{\"id\":\"O_2\",\"name\":\"In Progress\"}]}]}"

  let assert Ok(fields) = resolution.parse_project_fields(field_list_json)

  let assert Ok(field) = resolution.find_status_field(fields, "Status")

  let result = resolution.find_status_option(field, "Todo")

  result
  |> should.equal(option.Some(StatusOption(id: "O_1", name: "Todo")))
}

pub fn find_status_option_case_insensitive_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"},{\"id\":\"O_2\",\"name\":\"In Progress\"}]}]}"

  let assert Ok(fields) = resolution.parse_project_fields(field_list_json)

  let assert Ok(field) = resolution.find_status_field(fields, "Status")

  let result = resolution.find_status_option(field, "todo")

  result
  |> should.not_equal(option.None)
}

pub fn find_option_id_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"},{\"id\":\"O_2\",\"name\":\"In Progress\"}]}]}"

  let assert Ok(fields) = resolution.parse_project_fields(field_list_json)

  let result = resolution.find_option_id(fields, "Status", "Todo")

  result
  |> should.equal(Ok("O_1"))
}

pub fn find_option_id_not_found_test() {
  let field_list_json =
    "{\"fields\":[{\"id\":\"F_1\",\"name\":\"Status\",\"options\":[{\"id\":\"O_1\",\"name\":\"Todo\"}]}]}"

  let assert Ok(fields) = resolution.parse_project_fields(field_list_json)

  let result = resolution.find_option_id(fields, "Status", "Done")

  result
  |> should.be_error()
}
