// A proto3 scalar without presence is absent from JSON when it holds its zero,
// even when the input set it explicitly; the `optional` keyword is what keeps a
// zero on the page.

///|
test "a zero-valued field without presence is left out" {
  let schema = "syntax = \"proto3\";\npackage p;\nmessage M { int32 i = 1; string s = 2; optional int32 o = 3; }\n"
  let parsed = @parser.parse("p.proto", schema) catch {
    _ => abort("parse failed")
  }
  let file = @desc.build_file(parsed) catch { _ => abort("build failed") }
  let descriptor = file.messages[0]
  let message = @dynamic.Message::new(descriptor)
  let i = descriptor.field_by_name("i").unwrap()
  let s = descriptor.field_by_name("s").unwrap()
  message.set(i, @reflect.Int32(0))
  message.set(s, @reflect.String(""))
  let empty = encode(message) catch { _ => abort("encode failed") }
  assert_eq(empty, "{}")
  let o = descriptor.field_by_name("o").unwrap()
  message.set(o, @reflect.Int32(0))
  let kept = encode(message) catch { _ => abort("encode failed") }
  assert_eq(kept, "{\"o\":0}")
}

///|
test "binary and JSON leave the same zeros out" {
  let schema = "syntax = \"proto3\";\npackage p;\nmessage M { int32 i = 1; string s = 2; optional int32 o = 3; }\n"
  let parsed = @parser.parse("p.proto", schema) catch {
    _ => abort("parse failed")
  }
  let file = @desc.build_file(parsed) catch { _ => abort("build failed") }
  let descriptor = file.messages[0]
  let message = @dynamic.Message::new(descriptor)
  let i = descriptor.field_by_name("i").unwrap()
  let s = descriptor.field_by_name("s").unwrap()
  let o = descriptor.field_by_name("o").unwrap()
  message.set(i, @reflect.Int32(0))
  message.set(s, @reflect.String(""))
  // The binary encoder writes no bytes for the two zeros without presence.
  let binary = @proto.encode(message) catch { _ => abort("encode failed") }
  assert_eq(binary, b"")
  let empty = encode(message) catch { _ => abort("encode failed") }
  assert_eq(empty, "{}")
  // The one behind `optional` has presence, so both write it.
  message.set(o, @reflect.Int32(0))
  let kept_binary = @proto.encode(message) catch { _ => abort("encode failed") }
  assert_eq(kept_binary, b"\x18\x00")
  let kept = encode(message) catch { _ => abort("encode failed") }
  assert_eq(kept, "{\"o\":0}")
}

///|
test "a negative zero is written by both encodings" {
  let schema = "syntax = \"proto3\";\npackage p;\nmessage M { double d = 1; }\n"
  let parsed = @parser.parse("p.proto", schema) catch {
    _ => abort("parse failed")
  }
  let file = @desc.build_file(parsed) catch { _ => abort("build failed") }
  let descriptor = file.messages[0]
  let message = @dynamic.Message::new(descriptor)
  let d = descriptor.field_by_name("d").unwrap()
  message.set(d, @reflect.Double(-0.0))
  let binary = @proto.encode(message) catch { _ => abort("encode failed") }
  assert_eq(binary, b"\x09\x00\x00\x00\x00\x00\x00\x00\x80")
  let json = encode(message) catch { _ => abort("encode failed") }
  assert_eq(json, "{\"d\":-0}")
}
