// Presence is asked for, not assumed: a proto3 field written without a label
// has none, and only the `optional` keyword adds it. The label alone cannot
// decide, because proto3 labels an unlabelled field `optional` on the wire.

///|
test "a proto3 field without a label has no presence" {
  let source = "syntax = \"proto3\";\npackage p;\nmessage M { int32 i = 1; string s = 2; }\n"
  let file = parse("p.proto", source) catch { _ => abort("parse failed") }
  assert_true(file.message_type[0].field[0].proto3_optional == false)
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].fields[0].has_presence, false)
  assert_eq(built.messages[0].fields[1].has_presence, false)
}

///|
test "the optional keyword gives a proto3 field presence" {
  let source = "syntax = \"proto3\";\npackage p;\nmessage M { optional int32 i = 1; int32 plain = 2; }\n"
  let file = parse("p.proto", source) catch { _ => abort("parse failed") }
  assert_true(file.message_type[0].field[0].proto3_optional)
  assert_true(file.message_type[0].field[1].proto3_optional == false)
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].fields[0].has_presence, true)
  assert_eq(built.messages[0].fields[1].has_presence, false)
}

///|
test "proto2 and editions keep presence without the keyword" {
  let proto2 = "syntax = \"proto2\";\npackage p;\nmessage M { optional int32 i = 1; required int32 r = 2; }\n"
  let file = parse("p2.proto", proto2) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].fields[0].has_presence, true)
  assert_eq(built.messages[0].fields[1].has_presence, true)
  let editions = "edition = \"2023\";\npackage p;\nmessage M { int32 i = 1; }\n"
  let file2 = parse("e.proto", editions) catch { _ => abort("parse failed") }
  let built2 = @desc.build_file(file2) catch { _ => abort("build failed") }
  assert_eq(built2.messages[0].fields[0].has_presence, true)
}
