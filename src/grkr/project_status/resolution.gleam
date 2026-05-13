import gleam/list
import gleam/option
import grkr/issue_provider/ffi
import grkr/project_status/normalization
import grkr/project_status/types.{
  type StatusField, type StatusOption, StatusField, StatusOption,
}

pub fn parse_project_fields(
  field_list_json: String,
) -> Result(List(StatusField), String) {
  case ffi.parse(field_list_json) {
    Ok(obj) -> {
      let fields = case ffi.decode_array(ffi.get_field(obj, "fields")) {
        Ok(values) -> values
        Error(_) ->
          case ffi.decode_array(obj) {
            Ok(values) -> values
            Error(_) -> []
          }
      }

      parse_fields(fields)
    }
    Error(_) -> Error("Invalid field-list JSON")
  }
}

fn parse_fields(
  fields: List(ffi.JsonValue),
) -> Result(List(StatusField), String) {
  case fields {
    [] -> Ok([])
    [first, ..rest] ->
      case parse_field(first), parse_fields(rest) {
        Ok(field), Ok(parsed_rest) -> Ok([field, ..parsed_rest])
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
      }
  }
}

fn parse_field(field: ffi.JsonValue) -> Result(StatusField, String) {
  case get_string(field, "id"), get_string(field, "name") {
    option.Some(id), option.Some(name) ->
      Ok(StatusField(id: id, name: name, options: parse_options(field)))
    _, _ -> Error("Field missing id or name")
  }
}

fn parse_options(field: ffi.JsonValue) -> List(StatusOption) {
  case ffi.decode_array(ffi.get_field(field, "options")) {
    Ok(options) -> parse_option_values(options)
    Error(_) -> []
  }
}

fn parse_option_values(options: List(ffi.JsonValue)) -> List(StatusOption) {
  case options {
    [] -> []
    [first, ..rest] -> {
      let parsed_rest = parse_option_values(rest)
      case get_string(first, "id"), get_string(first, "name") {
        option.Some(id), option.Some(name) -> [
          StatusOption(id: id, name: name),
          ..parsed_rest
        ]
        _, _ -> parsed_rest
      }
    }
  }
}

pub fn find_status_field(
  fields: List(StatusField),
  field_name: String,
) -> Result(StatusField, String) {
  case
    list.find(fields, fn(field) {
      normalization.names_match(field.name, field_name)
    })
  {
    Ok(field) -> Ok(field)
    Error(_) -> Error("Field not found: " <> field_name)
  }
}

pub fn find_status_option(
  field: StatusField,
  option_name: String,
) -> option.Option(StatusOption) {
  case list.find(field.options, fn(opt) { opt.name == option_name }) {
    Ok(opt) -> option.Some(opt)
    Error(_) ->
      case
        list.find(field.options, fn(opt) {
          normalization.names_match(opt.name, option_name)
        })
      {
        Ok(opt) -> option.Some(opt)
        Error(_) -> option.None
      }
  }
}

pub fn find_option_id(
  fields: List(StatusField),
  field_name: String,
  option_name: String,
) -> Result(String, String) {
  case find_status_field(fields, field_name) {
    Ok(field) ->
      case find_status_option(field, option_name) {
        option.Some(opt) -> Ok(opt.id)
        option.None -> Error("Option not found: " <> option_name)
      }
    Error(error) -> Error(error)
  }
}

pub fn find_field_and_option_ids(
  fields: List(StatusField),
  field_name: String,
  option_name: String,
) -> Result(#(String, String, String), String) {
  case find_status_field(fields, field_name) {
    Ok(field) ->
      case find_status_option(field, option_name) {
        option.Some(opt) -> Ok(#(field.id, opt.id, opt.name))
        option.None -> Error("Option not found: " <> option_name)
      }
    Error(error) -> Error(error)
  }
}

fn get_string(obj: ffi.JsonValue, field: String) -> option.Option(String) {
  case ffi.decode_string(ffi.get_field(obj, field)) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}
