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
