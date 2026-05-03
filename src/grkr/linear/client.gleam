import gleam/dynamic
import gleam/javascript/promise.{type Promise}
import grkr/linear/graphql
import grkr/linear/types

pub fn execute_query(
  token: types.LinearToken,
  query: types.GraphQLQuery,
) -> Promise(Result(types.GraphQLResponse, String)) {
  execute_graphql_request(token.access_token, query)
}

pub fn execute_safe_query(
  token: types.LinearToken,
  query: types.GraphQLQuery,
) -> Promise(Result(types.GraphQLResponse, String)) {
  case graphql.is_query_safe(query) {
    True -> execute_query(token, query)
    False ->
      promise.resolve(Error("Mutation queries are not safe for E2E tests"))
  }
}

pub fn fetch_viewer(
  token: types.LinearToken,
) -> Promise(Result(types.LinearUser, String)) {
  execute_safe_query(token, graphql.viewer_query())
  |> promise.map(fn(result) {
    case result {
      Error(err) -> Error(err)
      Ok(response) ->
        case response.data {
          Ok(data) -> parse_viewer_data(data)
          Error(err) -> Error(err)
        }
    }
  })
}

pub fn fetch_projects(
  token: types.LinearToken,
) -> Promise(Result(List(types.LinearProject), String)) {
  execute_safe_query(token, graphql.projects_query())
  |> promise.map(fn(result) {
    case result {
      Error(err) -> Error(err)
      Ok(response) ->
        case response.data {
          Ok(data) -> parse_projects_data(data)
          Error(err) -> Error(err)
        }
    }
  })
}

pub fn fetch_teams(
  token: types.LinearToken,
) -> Promise(Result(List(types.LinearTeam), String)) {
  execute_safe_query(token, graphql.teams_query())
  |> promise.map(fn(result) {
    case result {
      Error(err) -> Error(err)
      Ok(response) ->
        case response.data {
          Ok(data) -> parse_teams_data(data)
          Error(err) -> Error(err)
        }
    }
  })
}

fn parse_viewer_data(
  data: dynamic.Dynamic,
) -> Result(types.LinearUser, String) {
  parse_viewer_json(data)
}

fn parse_projects_data(
  data: dynamic.Dynamic,
) -> Result(List(types.LinearProject), String) {
  parse_projects_json(data)
}

fn parse_teams_data(
  data: dynamic.Dynamic,
) -> Result(List(types.LinearTeam), String) {
  parse_teams_json(data)
}

@external(javascript, "../linear/client_ffi.mjs", "execute_graphql_request")
fn execute_graphql_request(
  token: String,
  query: types.GraphQLQuery,
) -> Promise(Result(types.GraphQLResponse, String))

@external(javascript, "../linear/client_ffi.mjs", "parse_viewer_json")
fn parse_viewer_json(data: dynamic.Dynamic) -> Result(types.LinearUser, String)

@external(javascript, "../linear/client_ffi.mjs", "parse_projects_json")
fn parse_projects_json(
  data: dynamic.Dynamic,
) -> Result(List(types.LinearProject), String)

@external(javascript, "../linear/client_ffi.mjs", "parse_teams_json")
fn parse_teams_json(
  data: dynamic.Dynamic,
) -> Result(List(types.LinearTeam), String)
