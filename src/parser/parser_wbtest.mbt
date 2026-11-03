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
