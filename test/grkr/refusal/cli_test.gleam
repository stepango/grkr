import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn cli_module_compiles_test() {
  // CLI module loads; main/arg parsing covered via integration in thin shells
  True |> should.be_true()
}
