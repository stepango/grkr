import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/list
import grkr/linear/client
import grkr/linear/config
import grkr/linear/types

pub fn run_e2e(_: Nil) -> Promise(types.E2ETestResult) {
  io.println("Starting Linear E2E tests...")

  case config.load_e2e_config() {
    Error(err) -> promise.resolve(types.E2ETestFailed(err))
    Ok(e2e_config) ->
      case e2e_config.enabled {
        False -> {
          io.println("E2E tests are disabled. Set GRKR_LINEAR_E2E=1 to enable.")
          promise.resolve(types.E2ETestBlocked(
            "E2E disabled by environment variable",
          ))
        }
        True -> {
          io.println("E2E tests enabled.")
          io.println("Config: " <> config.redact_config(e2e_config))

          case e2e_config.token {
            Error(Nil) -> {
              io.println("No Linear access token available.")
              io.println(
                "OAuth app credentials are present; complete OAuth install/token exchange and configure GRKR_LINEAR_TOKEN_PATH, ~/.linear/token.txt, or GRKR_LINEAR_ACCESS_TOKEN for live e2e.",
              )
              promise.resolve(types.E2ETestBlocked(
                "No Linear access token available - OAuth app credentials require installation/token exchange",
              ))
            }
            Ok(token) -> {
              io.println("Access token available, running live tests...")
              run_live_tests(token)
            }
          }
        }
      }
  }
}

fn run_live_tests(token: types.LinearToken) -> Promise(types.E2ETestResult) {
  io.println("Fetching viewer info...")
  client.fetch_viewer(token)
  |> promise.await(fn(viewer_result) {
    case viewer_result {
      Error(err) -> {
        io.println("Failed to fetch viewer: " <> err)
        promise.resolve(types.E2ETestFailed("Failed to fetch viewer: " <> err))
      }
      Ok(viewer) -> {
        io.println("Viewer: " <> viewer.name <> " <" <> viewer.email <> ">")

        io.println("Fetching projects...")
        client.fetch_projects(token)
        |> promise.await(fn(projects_result) {
          case projects_result {
            Error(err) -> {
              io.println("Failed to fetch projects: " <> err)
              promise.resolve(types.E2ETestFailed(
                "Failed to fetch projects: " <> err,
              ))
            }
            Ok(projects) -> {
              io.println(
                "Found " <> int_to_string(list.length(projects)) <> " projects",
              )

              io.println("Fetching teams...")
              client.fetch_teams(token)
              |> promise.await(fn(teams_result) {
                case teams_result {
                  Error(err) -> {
                    io.println("Failed to fetch teams: " <> err)
                    promise.resolve(types.E2ETestFailed(
                      "Failed to fetch teams: " <> err,
                    ))
                  }
                  Ok(teams) -> {
                    io.println(
                      "Found " <> int_to_string(list.length(teams)) <> " teams",
                    )
                    run_live_mutations(token, teams)
                    |> promise.map(fn(mutation_result) {
                      case mutation_result {
                        Error(err) -> types.E2ETestFailed(err)
                        Ok(summary) -> {
                          io.println("All E2E tests passed!")
                          types.E2ETestSuccess(
                            viewer,
                            projects,
                            teams,
                            Ok(summary),
                          )
                        }
                      }
                    })
                  }
                }
              })
            }
          }
        })
      }
    }
  })
}

fn run_live_mutations(
  token: types.LinearToken,
  teams: List(types.LinearTeam),
) -> Promise(Result(types.LinearLiveMutationSummary, String)) {
  case list.first(teams) {
    Error(_) ->
      promise.resolve(Error(
        "No Linear teams available for live e2e issue creation",
      ))
    Ok(team) -> {
      let title = "grkr Linear live e2e temporary issue"
      let description =
        "Temporary grkr live e2e issue. The harness archives this issue after creating a checkpoint comment."
      io.println(
        "Creating temporary Linear issue in discovered team "
        <> team.key
        <> "...",
      )
      client.create_issue(token, team.id, title, description)
      |> promise.await(fn(create_result) {
        case create_result {
          Error(err) ->
            promise.resolve(Error(
              "Failed to create temporary Linear issue: " <> err,
            ))
          Ok(issue) -> {
            io.println("Created temporary Linear issue: " <> issue.url)
            verify_and_comment_on_issue(token, issue)
          }
        }
      })
    }
  }
}

fn verify_and_comment_on_issue(
  token: types.LinearToken,
  issue: types.LinearIssue,
) -> Promise(Result(types.LinearLiveMutationSummary, String)) {
  client.fetch_issue(token, issue.id)
  |> promise.await(fn(fetch_result) {
    case fetch_result {
      Error(err) ->
        cleanup_after_failure(
          token,
          issue,
          "Failed to read temporary Linear issue: " <> err,
        )
      Ok(read_issue) -> {
        let body =
          "<!-- grkr:checkpoint:linear-live-e2e -->\n## grkr Linear live e2e checkpoint\n\nTemporary checkpoint comment created by the opt-in Linear live e2e harness."
        io.println(
          "Adding grkr checkpoint comment to temporary Linear issue...",
        )
        client.create_comment(token, read_issue.id, body)
        |> promise.await(fn(comment_result) {
          case comment_result {
            Error(err) ->
              cleanup_after_failure(
                token,
                read_issue,
                "Failed to create Linear checkpoint comment: " <> err,
              )
            Ok(comment) -> cleanup_after_success(token, read_issue, comment)
          }
        })
      }
    }
  })
}

fn cleanup_after_success(
  token: types.LinearToken,
  issue: types.LinearIssue,
  comment: types.LinearComment,
) -> Promise(Result(types.LinearLiveMutationSummary, String)) {
  io.println("Archiving temporary Linear issue for cleanup...")
  client.archive_issue(token, issue.id)
  |> promise.map(fn(archive_result) {
    case archive_result {
      Error(err) ->
        Error(
          "Created temporary Linear issue "
          <> issue.url
          <> " but cleanup/archive failed: "
          <> err,
        )
      Ok(archive) ->
        Ok(types.LinearLiveMutationSummary(issue, comment, archive.success))
    }
  })
}

fn cleanup_after_failure(
  token: types.LinearToken,
  issue: types.LinearIssue,
  error: String,
) -> Promise(Result(types.LinearLiveMutationSummary, String)) {
  client.archive_issue(token, issue.id)
  |> promise.map(fn(_) {
    Error(error <> " (temporary issue cleanup attempted)")
  })
}

pub fn format_test_result(result: types.E2ETestResult) -> String {
  case result {
    types.E2ETestSuccess(viewer, projects, teams, live_mutation) -> {
      let mutation_line = case live_mutation {
        Ok(summary) ->
          "\nTemporary issue: "
          <> summary.issue.url
          <> "\nCheckpoint comment: "
          <> summary.comment.id
          <> "\nArchived: "
          <> bool_to_string(summary.archived)
        Error(_) -> "\nLive mutations: not run"
      }

      "E2E Tests Passed\n"
      <> "Viewer: "
      <> viewer.name
      <> " <"
      <> viewer.email
      <> ">\n"
      <> "Projects: "
      <> int_to_string(list.length(projects))
      <> "\n"
      <> "Teams: "
      <> int_to_string(list.length(teams))
      <> mutation_line
    }
    types.E2ETestBlocked(reason) -> {
      "E2E Tests Blocked: " <> reason
    }
    types.E2ETestFailed(error) -> {
      "E2E Tests Failed: " <> error
    }
  }
}

pub fn should_exit_success(result: types.E2ETestResult) -> Bool {
  case result {
    types.E2ETestSuccess(_, _, _, _) -> True
    types.E2ETestBlocked(_) -> True
    types.E2ETestFailed(_) -> False
  }
}

fn int_to_string(i: Int) -> String {
  builtin_int_to_string(i)
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

@external(javascript, "../linear/e2e_ffi.mjs", "int_to_string")
fn builtin_int_to_string(i: Int) -> String
