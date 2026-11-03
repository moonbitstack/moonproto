// The JSON mapping's fixed points: names, 64-bit integers as strings, enums by
// name, bytes as base64, and the well-known time forms.

///|
fn make_field(
  number : Int32,
  name : String,
  kind : @reflect.Kind,
  enum_type : String?,
  containing : String,
) -> @reflect.FieldDescriptor {
  {
    name,
    full_name: containing + "." + name,
    number,
    kind,
    cardinality: @reflect.Optional,
    json_name: name,
    text_name: name,
    has_presence: false,
    is_extension: false,
    is_map: false,
    packed: false,
    oneof_index: None,
    message_type: None,
    enum_type,
    has_default: false,
    default_value: @reflect.Invalid,
    default_enum_name: None,
    containing_message: containing,
    map_key_field: None,
    map_value_field: None,
  }
}

///|
fn message_descriptor(
  full_name : String,
  fields : Array[@reflect.FieldDescriptor],
) -> @reflect.MessageDescriptor {
  {
    name: "M",
    full_name,
    syntax: @reflect.Proto3,
    fields,
    oneofs: [],
    is_map_entry: false,
    reserved_names: [],
    reserved_ranges: [],
    required_numbers: [],
    extension_ranges: [],
    nested_messages: [],
    nested_enums: [],
    nested_extensions: [],
    file_path: "test.proto",
    map_key: None,
    map_value: None,
  }
}

///|
fn register_enum() -> Unit {
  let values : Array[@reflect.EnumValueDescriptor] = [
    { name: "FOO", number: 1, full_name: "test.Color.FOO", },
    { name: "BAR", number: 2, full_name: "test.Color.BAR", },
  ]
  let enum_desc : @reflect.EnumDescriptor = {
    name: "Color",
    full_name: "test.Color",
    values,
    closed: false,
    file_path: "test.proto",
  }
  let file : @reflect.FileDescriptor = {
    path: "test.proto",
    package_name: "test",
    syntax: @reflect.Proto3,
    messages: [],
    enums: [enum_desc],
    services: [],
    extensions: [],
    dependencies: [],
    public_dependencies: [],
    edition: None,
    option_map: [],
  }
  @reflect.global_files.register(file) catch {
    _ => ()
  }
}

///|
test "the scalar mapping and its fixed text" {
  register_enum()
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let l = make_field(2, "l", @reflect.Int64, None, "test.M")
  let s = make_field(3, "s", @reflect.String, None, "test.M")
  let by = make_field(4, "by", @reflect.Bytes, None, "test.M")
  let b = make_field(5, "b", @reflect.Bool, None, "test.M")
  let e = make_field(6, "e", @reflect.Enum, Some("test.Color"), "test.M")
  let desc = message_descriptor("test.M", [i, l, s, by, b, e])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(150))
  m.set(l, @reflect.Int64(10_000_000_000L))
  m.set(s, @reflect.String("hi"))
  m.set(by, @reflect.Bytes(b"\x01\x02"))
  m.set(b, @reflect.Bool(true))
  m.set(e, @reflect.Enum(2))
  let text = encode(m)
  assert_eq(
    text, "{\"i\":150,\"l\":\"10000000000\",\"s\":\"hi\",\"by\":\"AQI=\",\"b\":true,\"e\":\"BAR\"}",
  )
  let back = @dynamic.Message::new(desc)
  decode(text, back)
  assert_eq(back.get(i).int(), 150L)
  assert_eq(back.get(l).int(), 10_000_000_000L)
  assert_eq(back.get(s).string(), "hi")
  assert_eq(back.get(by).bytes(), b"\x01\x02")
  assert_eq(back.get(b).bool(), true)
  assert_eq(back.get(e).enum_number(), 2)
}

///|
test "an unknown JSON name is refused unless discarded" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  let hit = try {
    decode("{\"nope\":1}", m)
    false
  } catch {
    UnknownField(_) => true
    _ => false
  }
  assert_true(hit)
  decode("{\"nope\":1}", m, unmarshal_options={
    ..unmarshal_options,
    discard_unknown: true,
  })
}

///|
test "emit_unpopulated writes defaults" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let s = make_field(2, "s", @reflect.String, None, "test.M")
  let desc = message_descriptor("test.M", [i, s])
  let m = @dynamic.Message::new(desc)
  let text = encode(m, marshal_options={
    ..marshal_options,
    emit_unpopulated: true,
  })
  assert_eq(text, "{\"i\":0,\"s\":\"\"}")
}

///|
test "multiline output indents" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(1))
  let text = encode(m, marshal_options={ ..marshal_options, multiline: true, })
  assert_true(text.contains("\n"))
}

///|
test "Timestamp is an RFC 3339 string" {
  let seconds = make_field(
    1,
    "seconds",
    @reflect.Int64,
    None,
    "google.protobuf.Timestamp",
  )
  let nanos = make_field(
    2,
    "nanos",
    @reflect.Int32,
    None,
    "google.protobuf.Timestamp",
  )
  let desc = message_descriptor("google.protobuf.Timestamp", [seconds, nanos])
  let m = @dynamic.Message::new(desc)
  m.set(seconds, @reflect.Int64(0L))
  assert_eq(encode(m), "\"1970-01-01T00:00:00Z\"")
  let back = @dynamic.Message::new(desc)
  decode("\"1970-01-01T00:00:00Z\"", back)
  assert_eq(back.get(seconds).int(), 0L)
  let later = @dynamic.Message::new(desc)
  decode("\"2026-11-03T19:42:45Z\"", later)
  assert_eq(encode(later), "\"2026-11-03T19:42:45Z\"")
}

///|
test "Duration is a seconds string" {
  let seconds = make_field(
    1,
    "seconds",
    @reflect.Int64,
    None,
    "google.protobuf.Duration",
  )
  let nanos = make_field(
    2,
    "nanos",
    @reflect.Int32,
    None,
    "google.protobuf.Duration",
  )
  let desc = message_descriptor("google.protobuf.Duration", [seconds, nanos])
  let m = @dynamic.Message::new(desc)
  m.set(seconds, @reflect.Int64(1L))
  m.set(nanos, @reflect.Int32(500_000_000))
  assert_eq(encode(m), "\"1.500000000s\"")
  let back = @dynamic.Message::new(desc)
  decode("\"1.500000000s\"", back)
  assert_eq(back.get(seconds).int(), 1L)
  assert_eq(back.get(nanos).int(), 500_000_000L)
}

// -- arbitrary JSON through Struct, Value and ListValue ----------------------

///|
fn known_desc(name : String) -> @reflect.MessageDescriptor {
  @known.register_all()
  match (@known.message_descriptor(name) catch { _ => None }) {
    Some(desc) => desc
    None => abort("missing " + name)
  }
}

///|
test "Struct carries arbitrary JSON both ways" {
  let desc = known_desc("google.protobuf.Struct")
  let m = @dynamic.Message::new(desc)
  let source = "{\"a\":1,\"b\":[\"x\",true,null],\"c\":{\"d\":2}}"
  decode(source, m)
  let text = encode(m)
  // Object key order is not part of the format, so compare through a parse.
  let expected = @cjson.parse(source) catch { _ => abort("bad fixture") }
  let got = @cjson.parse(text) catch { _ => abort("bad output") }
  assert_true(got == expected)
}

///|
test "a Value holds whichever JSON kind it was given" {
  let desc = known_desc("google.protobuf.Value")
  let cases : Array[(String, String)] = [
    ("null", "null"),
    ("true", "true"),
    ("7", "7"),
    ("\"hi\"", "\"hi\""),
    ("[1,2]", "[1,2]"),
    ("{\"k\":false}", "{\"k\":false}"),
  ]
  for item in cases {
    let m = @dynamic.Message::new(desc)
    decode(item.0, m)
    assert_eq(encode(m), item.1)
  }
}

///|
test "ListValue is an array" {
  let desc = known_desc("google.protobuf.ListValue")
  let m = @dynamic.Message::new(desc)
  decode("[1,\"two\",null]", m)
  assert_eq(encode(m), "[1,\"two\",null]")
}

///|
test "a Struct field inside a message uses the same mapping" {
  let struct_desc = known_desc("google.protobuf.Struct")
  let struct_type = @dynamic.new_message_type(struct_desc)
  @reflect.global_types.register_message(struct_type) catch {
    _ => ()
  }
  let field : @reflect.FieldDescriptor = {
    ..make_field(1, "s", @reflect.Message, None, "test.Holder"),
    message_type: Some("google.protobuf.Struct"),
  }
  let desc = message_descriptor("test.Holder", [field])
  let m = @dynamic.Message::new(desc)
  decode("{\"s\":{\"n\":3}}", m)
  assert_eq(encode(m), "{\"s\":{\"n\":3}}")
}

// -- extensions in JSON ------------------------------------------------------

///|
test "an extension is keyed by its bracketed full name" {
  let desc = message_descriptor_with_extensions("test.JsonExt")
  let ext : @reflect.FieldDescriptor = {
    ..make_field(100, "my_ext", @reflect.Int32, None, "test.JsonExt"),
    full_name: "test.my_ext",
    is_extension: true,
  }
  let extension_type = @dynamic.new_extension_type(ext)
  @reflect.global_types.register_extension(extension_type) catch {
    _ => ()
  }
  let m = @dynamic.Message::new(desc)
  let field = match desc.field_by_number(1) {
    Some(found) => found
    None => abort("missing field")
  }
  m.set(field, @reflect.Int32(1))
  m.set(ext, @reflect.Int32(42))
  let text = encode(m)
  assert_true(text.contains("\"[test.my_ext]\":42"))
  let back = @dynamic.Message::new(desc)
  decode(text, back)
  assert_eq(back.get(ext).int(), 42L)
}

///|
fn message_descriptor_with_extensions(
  full_name : String,
) -> @reflect.MessageDescriptor {
  {
    name: "JsonExt",
    full_name,
    syntax: @reflect.Proto2,
    fields: [make_field(1, "i", @reflect.Int32, None, full_name)],
    oneofs: [],
    is_map_entry: false,
    reserved_names: [],
    reserved_ranges: [],
    required_numbers: [],
    extension_ranges: [(100, 200)],
    nested_messages: [],
    nested_enums: [],
    nested_extensions: [],
    file_path: "test.proto",
    map_key: None,
    map_value: None,
  }
}

///|
test "JSON refuses a required field that is unset" {
  let field = make_field(1, "must", @reflect.Int32, None, "test.Req")
  let desc : @reflect.MessageDescriptor = {
    name: "Req",
    full_name: "test.Req",
    syntax: @reflect.Proto2,
    fields: [field],
    oneofs: [],
    is_map_entry: false,
    reserved_names: [],
    reserved_ranges: [],
    required_numbers: [1],
    extension_ranges: [],
    nested_messages: [],
    nested_enums: [],
    nested_extensions: [],
    file_path: "test.proto",
    map_key: None,
    map_value: None,
  }
  let message = @dynamic.Message::new(desc)
  let refused = try {
    let _ = encode(message)
    false
  } catch {
    Required(_) => true
    _ => false
  }
  assert_true(refused)
  let text = encode(message, marshal_options={
    ..marshal_options,
    allow_partial: true,
  }) catch {
    _ => abort("allow_partial still refused")
  }
  assert_eq(text, "{}")
}
