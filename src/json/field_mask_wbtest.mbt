// A FieldMask travels as one comma-separated string of lowerCamelCase paths,
// while the message holds the same paths in snake_case.

///|
test "a FieldMask is one string of lowerCamelCase paths" {
  @known.register_all()
  let mask = @protobuf.FieldMask::new()
  decode("\"userName,displayName\"", mask) catch {
    _ => abort("decode failed")
  }
  assert_eq(mask.paths().length(), 2)
  assert_eq(mask.paths().get(0).string(), "user_name")
  assert_eq(mask.paths().get(1).string(), "display_name")
  let encoded = encode(mask) catch { _ => abort("encode failed") }
  assert_eq(encoded, "\"userName,displayName\"")
}

///|
test "a nested FieldMask path keeps its dots" {
  @known.register_all()
  let mask = @protobuf.FieldMask::new()
  decode("\"foo.barBaz\"", mask) catch {
    _ => abort("decode failed")
  }
  assert_eq(mask.paths().get(0).string(), "foo.bar_baz")
  let encoded = encode(mask) catch { _ => abort("encode failed") }
  assert_eq(encoded, "\"foo.barBaz\"")
}
