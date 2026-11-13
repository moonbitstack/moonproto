// Packing is decided once, from the schema: an option written on a field, or
// the default its syntax gives it. The binary encoder asks the descriptor and
// never guesses.

///|
fn packed_bytes_of(source : String, field_name : String) -> Bytes {
  let shape = @parser.parse("packed.proto", source) catch {
    _ => abort("bad schema")
  }
  let file = @desc.build_file(shape) catch { _ => abort("bad descriptor") }
  let descriptor = file.messages[0]
  let field = descriptor.field_by_name(field_name).unwrap()
  let message = @dynamic.Message::new(descriptor)
  let list = message.mutable(field).list()
  list.append(@reflect.Int32(1))
  list.append(@reflect.Int32(2))
  encode(message) catch {
    _ => abort("encode failed")
  }
}

///|
test "a proto2 field declared packed is written as one length-delimited run" {
  let source = "syntax = \"proto2\";\nmessage M { repeated int32 xs = 1 [packed = true]; }\n"
  assert_eq(packed_bytes_of(source, "xs"), b"\x0a\x02\x01\x02")
}

///|
test "a proto2 field without the option repeats its tag" {
  let source = "syntax = \"proto2\";\nmessage M { repeated int32 xs = 1; }\n"
  assert_eq(packed_bytes_of(source, "xs"), b"\x08\x01\x08\x02")
}

///|
test "a proto2 field declared unpacked repeats its tag" {
  let source = "syntax = \"proto2\";\nmessage M { repeated int32 xs = 1 [packed = false]; }\n"
  assert_eq(packed_bytes_of(source, "xs"), b"\x08\x01\x08\x02")
}

///|
test "a proto3 field is packed unless the option expands it" {
  let packed = "syntax = \"proto3\";\nmessage M { repeated int32 xs = 1; }\n"
  assert_eq(packed_bytes_of(packed, "xs"), b"\x0a\x02\x01\x02")
  let expanded = "syntax = \"proto3\";\nmessage M { repeated int32 xs = 1 [packed = false]; }\n"
  assert_eq(packed_bytes_of(expanded, "xs"), b"\x08\x01\x08\x02")
}

///|
test "an editions field takes the feature on the field over the file default" {
  let source = "edition = \"2023\";\n" +
    "option features.repeated_field_encoding = EXPANDED;\n" +
    "message M { repeated int32 xs = 1 [features.repeated_field_encoding = PACKED]; }\n"
  assert_eq(packed_bytes_of(source, "xs"), b"\x0a\x02\x01\x02")
}
