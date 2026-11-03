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
