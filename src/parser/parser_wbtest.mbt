// Parsing a real file and building it into descriptors that encode.

///|
const SOURCE : String = "syntax = \"proto3\";\n" +
  "package test;\n" +
  "\n" +
  "enum Color { RED = 0; BLUE = 1; }\n" +
  "\n" +
  "message Inner { int32 x = 1; }\n" +
  "\n" +
  "message M {\n" +
  "  int32 i = 1;\n" +
  "  string s = 2;\n" +
  "  repeated int32 nums = 3;\n" +
  "  map<string, int32> counts = 4;\n" +
  "  Inner inner = 5;\n" +
  "  Color color = 6;\n" +
  "  oneof pick { int32 a = 7; string b = 8; }\n" +
  "  reserved 100 to 110;\n" +
  "  reserved \"old\";\n" +
  "}\n"

///|
test "the file shape" {
  let file = parse("test.proto", SOURCE) catch { _ => abort("parse failed") }
  assert_eq(file.package_name, "test")
  assert_eq(file.syntax, "proto3")
  assert_eq(file.message_type.length(), 2)
  assert_eq(file.enum_type.length(), 1)
}

///|
test "field kinds, cardinality and references" {
  let file = parse("test.proto", SOURCE) catch { _ => abort("parse failed") }
  let m = file.message_type[1]
  assert_eq(m.name, "M")
  assert_eq(m.field.length(), 8)
  let i = m.field[0]
  assert_eq(i.name, "i")
  assert_eq(i.type_code, 5)
  let nums = m.field[2]
  assert_eq(nums.label, 3)
  // proto3 repeated numeric is packed by the builder.
  let counts = m.field[3]
  assert_eq(counts.label, 3)
  assert_eq(counts.type_code, 11)
  match counts.type_name {
    Some(name) => assert_eq(name, "test.M.CountsEntry")
    None => abort("no type name")
  }
  assert_eq(m.nested_type.length(), 1)
  assert_true(m.nested_type[0].map_entry)
  let inner = m.field[4]
  assert_true(inner.type_name == Some("test.Inner"))
  let color = m.field[5]
  assert_eq(color.type_code, 14)
  assert_true(color.type_name == Some("test.Color"))
  assert_eq(m.oneof_decl.length(), 1)
  assert_eq(m.field[6].oneof_index, Some(0))
  assert_eq(m.reserved_range.length(), 1)
  assert_eq(m.reserved_range[0].0, 100)
  assert_eq(m.reserved_name.length(), 1)
}

///|
test "the parsed file builds and encodes" {
  let file = parse("test.proto", SOURCE) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  let mut found = None
  for item in built.messages {
    if item.name == "M" {
      found = Some(item)
    }
  }
  let desc = match found {
    Some(m) => m
    None => abort("missing M")
  }
  let message = @dynamic.Message::new(desc)
  let i = match desc.field_by_number(1) {
    Some(f) => f
    None => abort("missing i")
  }
  message.set(i, @reflect.Int32(150))
  let bytes = @proto.encode(message)
  assert_eq(bytes, b"\x08\x96\x01")
  let back = @dynamic.Message::new(desc)
  @proto.decode(bytes, back)
  assert_eq(back.get(i).int(), 150L)
}

///|
test "a proto2 required field is reported" {
  let source = "syntax = \"proto2\";\npackage p;\nmessage P { required int32 must = 1; }\n"
  let file = parse("p.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].required_numbers.length(), 1)
}

///|
test "services and rpcs" {
  let source = "syntax = \"proto3\";\npackage s;\nmessage Req {}\nmessage Rep {}\nservice S { rpc Get (Req) returns (Rep); rpc Watch (stream Req) returns (stream Rep); }\n"
  let file = parse("s.proto", source) catch { _ => abort("parse failed") }
  assert_eq(file.service.length(), 1)
  assert_eq(file.service[0].methods.length(), 2)
  assert_true(file.service[0].methods[1].client_streaming)
  assert_true(file.service[0].methods[1].server_streaming)
}

// -- editions and options ----------------------------------------------------

///|
test "editions default to explicit presence" {
  let source = "edition = \"2023\";\npackage e;\nmessage M { int32 a = 1; }\n"
  let file = parse("e.proto", source) catch { _ => abort("parse failed") }
  assert_true(file.edition == Some("2023"))
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_true(built.syntax == @reflect.Editions)
  assert_eq(built.messages[0].fields[0].has_presence, true)
}

///|
test "features.field_presence = IMPLICIT removes presence" {
  let source = "edition = \"2023\";\npackage e;\noption features.field_presence = IMPLICIT;\nmessage M { int32 a = 1; }\n"
  let file = parse("e.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].fields[0].has_presence, false)
}

///|
test "features.repeated_field_encoding = EXPANDED turns packing off" {
  let source = "edition = \"2023\";\npackage e;\noption features.repeated_field_encoding = EXPANDED;\nmessage M { repeated int32 nums = 1; }\n"
  let file = parse("e.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].fields[0].packed, false)
  assert_eq(built.messages[0].fields[0].has_presence, true)
}

///|
test "a field feature overrides the message and the file" {
  let source = "edition = \"2023\";\npackage e;\noption features.field_presence = IMPLICIT;\nmessage M {\n  int32 implicit = 1;\n  int32 explicit = 2 [features.field_presence = EXPLICIT];\n}\n"
  let file = parse("e.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.messages[0].fields[0].has_presence, false)
  assert_eq(built.messages[0].fields[1].has_presence, true)
}

///|
test "features.enum_type = CLOSED closes the enum" {
  let source = "edition = \"2023\";\npackage e;\nenum Color { option features.enum_type = CLOSED; RED = 0; }\n"
  let file = parse("e.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.enums[0].closed, true)
}

///|
test "features.message_encoding = DELIMITED is a group on the wire" {
  let source = "edition = \"2023\";\npackage e;\nmessage Inner { int32 i = 1; }\nmessage M {\n  option features.message_encoding = DELIMITED;\n  Inner inner = 1;\n}\n"
  let file = parse("e.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  let m = built.messages[1]
  assert_true(m.fields[0].kind == @reflect.Group)
}

///|
test "custom options survive on the declaration they were written on" {
  let source = "syntax = \"proto3\";\npackage o;\noption (test.file_opt) = \"f\";\nmessage M {\n  option (test.msg_opt) = true;\n  int32 a = 1 [(test.field_opt) = 7, deprecated = true];\n}\n"
  let file = parse("o.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(built.option_of("", "(test.file_opt)"), Some("f"))
  assert_eq(built.option_of("o.M", "(test.msg_opt)"), Some("true"))
  assert_eq(built.option_of("o.M.a", "(test.field_opt)"), Some("7"))
  assert_eq(built.option_of("o.M.a", "deprecated"), Some("true"))
}

///|
test "an option whose value is a message keeps the aggregate" {
  let source = "syntax = \"proto3\";\npackage a;\noption (test.file_opt) = { name: \"x\", n: 1 };\nmessage M { int32 a = 1 [(test.field_opt) = { flag: true }]; }\n"
  let file = parse("a.proto", source) catch { _ => abort("parse failed") }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  assert_eq(
    built.option_of("", "(test.file_opt)"),
    Some("{ name: \"x\", n: 1 }"),
  )
  assert_eq(
    built.option_of("a.M.a", "(test.field_opt)"),
    Some("{ flag: true }"),
  )
}
