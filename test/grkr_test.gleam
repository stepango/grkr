import grkr/linear/config_test
import grkr/linear/e2e_test
import grkr/linear/graphql_test
import grkr/resolve_pr/codex_test
import grkr/resolve_pr/types_test

pub fn main() {
  config_test.main()
  e2e_test.main()
  graphql_test.main()
  types_test.main()
  codex_test.main()
}
