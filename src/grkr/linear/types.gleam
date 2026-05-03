import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}

pub type OAuthCredentials {
  OAuthCredentials(
    client_id: String,
    client_secret: String,
  )
}

pub type LinearToken {
  LinearToken(access_token: String)
}

pub type E2EConfig {
  E2EConfig(
    credentials: OAuthCredentials,
    token: Result(LinearToken, Nil),
    enabled: Bool,
  )
}

pub type LinearUser {
  LinearUser(
    id: String,
    name: String,
    email: String,
  )
}

pub type LinearProject {
  LinearProject(
    id: String,
    name: String,
    url: String,
  )
}

pub type LinearTeam {
  LinearTeam(
    id: String,
    name: String,
    key: String,
  )
}

pub type LinearIssue {
  LinearIssue(
    id: String,
    title: String,
    description: String,
    url: String,
    state_id: String,
  )
}

pub type GraphQLQuery {
  GraphQLQuery(
    query: String,
    variables: Dict(String, String),
  )
}

pub type GraphQLResponse {
  GraphQLResponse(
    data: Result(Dynamic, String),
    errors: List(String),
  )
}

pub type E2ETestResult {
  E2ETestSuccess(
    viewer: LinearUser,
    projects: List(LinearProject),
    teams: List(LinearTeam),
  )
  E2ETestBlocked(reason: String)
  E2ETestFailed(error: String)
}
