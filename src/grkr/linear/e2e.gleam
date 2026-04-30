import grkr/linear/types
import grkr/linear/config
import grkr/linear/client
import gleam/list
import gleam/io

pub fn run_e2e_tests() -> types.E2ETestResult {
  io.println("Starting Linear E2E tests...")

  case config.load_e2e_config() {
    Error(err) -> types.E2ETestFailed(err)
    Ok(e2e_config) -> case e2e_config.enabled {
      False -> {
        io.println("E2E tests are disabled. Set GRKR_LINEAR_E2E=1 to enable.")
        types.E2ETestBlocked("E2E disabled by environment variable")
      }
      True -> {
        io.println("E2E tests enabled.")
        io.println("Config: " <> config.redact_config(e2e_config))

        case e2e_config.token {
          Error(Nil) -> {
            io.println("No Linear access token available.")
            io.println("OAuth app credentials are present; complete OAuth install/token exchange and set GRKR_LINEAR_ACCESS_TOKEN for live e2e.")
            types.E2ETestBlocked("No Linear access token available - OAuth app credentials require installation/token exchange")
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

fn run_live_tests(token: types.LinearToken) -> types.E2ETestResult {
  io.println("Fetching viewer info...")
  case client.fetch_viewer(token) {
    Error(err) -> {
      io.println("Failed to fetch viewer: " <> err)
      types.E2ETestFailed("Failed to fetch viewer: " <> err)
    }
    Ok(viewer) -> {
      io.println("Viewer: " <> viewer.name <> " <" <> viewer.email <> ">")

      io.println("Fetching projects...")
      case client.fetch_projects(token) {
        Error(err) -> {
          io.println("Failed to fetch projects: " <> err)
          types.E2ETestFailed("Failed to fetch projects: " <> err)
        }
        Ok(projects) -> {
          io.println("Found " <> int_to_string(list.length(projects)) <> " projects")

          io.println("Fetching teams...")
          case client.fetch_teams(token) {
            Error(err) -> {
              io.println("Failed to fetch teams: " <> err)
              types.E2ETestFailed("Failed to fetch teams: " <> err)
            }
            Ok(teams) -> {
              io.println("Found " <> int_to_string(list.length(teams)) <> " teams")
              io.println("All E2E tests passed!")
              types.E2ETestSuccess(viewer, projects, teams)
            }
          }
        }
      }
    }
  }
}

pub fn format_test_result(result: types.E2ETestResult) -> String {
  case result {
    types.E2ETestSuccess(viewer, projects, teams) -> {
      "E2E Tests Passed\n"
      <> "Viewer: " <> viewer.name <> " <" <> viewer.email <> ">\n"
      <> "Projects: " <> int_to_string(list.length(projects)) <> "\n"
      <> "Teams: " <> int_to_string(list.length(teams))
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
    types.E2ETestSuccess(_, _, _) -> True
    types.E2ETestBlocked(_) -> True
    types.E2ETestFailed(_) -> False
  }
}

fn int_to_string(i: Int) -> String {
  builtin_int_to_string(i)
}

@external(javascript, "../linear/e2e_ffi.mjs", "int_to_string")
fn builtin_int_to_string(i: Int) -> String
