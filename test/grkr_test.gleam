import grkr/issue_provider_test
import grkr/linear/config_test
import grkr/linear/e2e_test
import grkr/linear/graphql_test
import grkr/progress/checkpoint_id_test
import grkr/progress/checkpoint_render_test
import grkr/progress/checkpoint_stage_test
import grkr/progress/linear_mutation_test
import grkr/progress/linear_state_test
import grkr/progress/main_test as progress_main_test
import grkr/project_status/config_test as project_status_config_test
import grkr/project_status/extraction_test
import grkr/project_status/normalization_test
import grkr/project_status/planning_test
import grkr/project_status/resolution_test
import grkr/project_status/types_test as project_status_types_test
import grkr/resolve_pr/codex_test
import grkr/resolve_pr/types_test
import grkr/sync_main/main_test

pub fn main() {
  issue_provider_test.main()
  config_test.main()
  e2e_test.main()
  graphql_test.main()
  checkpoint_id_test.main()
  checkpoint_render_test.main()
  checkpoint_stage_test.main()
  linear_mutation_test.main()
  linear_state_test.main()
  progress_main_test.main()
  types_test.main()
  codex_test.main()
  main_test.main()
  project_status_types_test.main()
  project_status_config_test.main()
  normalization_test.main()
  extraction_test.main()
  resolution_test.main()
  planning_test.main()
}
