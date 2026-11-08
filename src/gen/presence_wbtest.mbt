// The struct shape follows presence, and presence follows the schema: a
// proto3 field without the `optional` keyword holds a value, not an option.

///|
test "a proto3 schema without labels generates plain fields" {
  let source = "syntax = \"proto3\";\npackage p;\nmessage M { int32 i = 1; string s = 2; optional int32 o = 3; }\n"
  let file = @parser.parse("p.proto", source) catch {
    _ => abort("parse failed")
  }
  let generated = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(generated.contains("mut i : Int32\n"))
  assert_true(generated.contains("mut s : String\n"))
  assert_true(generated.contains("mut o : Int32?\n"))
}
