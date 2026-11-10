// A proto3 field without presence has no set state of its own: it is on the
// wire only when its value differs from the zero of its kind, so writing a zero
// is the same as never writing the field. `optional` is what keeps a zero.
// Negative zero is a value, not a zero: the sign bit is part of it, and every
// format round-trips it.

///|
fn presence_message() -> (@reflect.MessageDescriptor, &@reflect.Message) {
  let schema = "syntax = \"proto3\";\n" +
    "package p;\n" +
    "message M { int32 i = 1; string s = 2; optional int32 o = 3; double d = 4; bytes b = 5; }\n"
  let parsed = @parser.parse("p.proto", schema) catch {
    _ => abort("parse failed")
  }
  let file = @desc.build_file(parsed) catch { _ => abort("build failed") }
  let descriptor = file.messages[0]
  (descriptor, @dynamic.Message::new(descriptor))
}

///|
test "binary: a zero without presence writes no bytes" {
  let (descriptor, message) = presence_message()
  let i = descriptor.field_by_name("i").unwrap()
  let s = descriptor.field_by_name("s").unwrap()
  let d = descriptor.field_by_name("d").unwrap()
  let b = descriptor.field_by_name("b").unwrap()
  message.set(i, @reflect.Int32(0))
  message.set(s, @reflect.String(""))
  message.set(d, @reflect.Double(0.0))
  message.set(b, @reflect.Bytes(b""))
  assert_true(!message.has(i))
  assert_true(!message.has(s))
  let bytes = encode(message) catch { _ => abort("encode failed") }
  assert_eq(bytes, b"")
  assert_eq(size(message), 0)
}

///|
test "binary: a zero behind optional writes its tag and value" {
  let (descriptor, message) = presence_message()
  let o = descriptor.field_by_name("o").unwrap()
  message.set(o, @reflect.Int32(0))
  assert_true(message.has(o))
  let bytes = encode(message) catch { _ => abort("encode failed") }
  // field 3, wire type 0: tag 0x18, then the zero varint.
  assert_eq(bytes, b"\x18\x00")
  assert_eq(size(message), 2)
}

///|
test "binary: a nonzero value is written as before" {
  let (descriptor, message) = presence_message()
  let i = descriptor.field_by_name("i").unwrap()
  message.set(i, @reflect.Int32(150))
  let bytes = encode(message) catch { _ => abort("encode failed") }
  assert_eq(bytes, b"\x08\x96\x01")
}

///|
test "binary: negative zero keeps its sign on the wire" {
  let (descriptor, message) = presence_message()
  let d = descriptor.field_by_name("d").unwrap()
  message.set(d, @reflect.Double(-0.0))
  assert_true(message.has(d))
  let bytes = encode(message) catch { _ => abort("encode failed") }
  // field 4, wire type 1: tag 0x21, then eight little-endian bytes with only
  // the sign bit set.
  assert_eq(bytes, b"\x21\x00\x00\x00\x00\x00\x00\x00\x80")
}

///|
test "binary: a zero read from the wire does not come back" {
  let (descriptor, message) = presence_message()
  let i = descriptor.field_by_name("i").unwrap()
  let s = descriptor.field_by_name("s").unwrap()
  // A sender may write an explicit zero even though a proto3 encoder would not.
  decode(b"\x08\x00\x12\x00", message) catch {
    _ => abort("decode failed")
  }
  assert_eq(message.get(i).int(), 0L)
  assert_eq(message.get(s).string(), "")
  assert_true(!message.has(i))
  assert_true(!message.has(s))
  let bytes = encode(message) catch { _ => abort("encode failed") }
  assert_eq(bytes, b"")
}
