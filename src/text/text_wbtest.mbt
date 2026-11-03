// The text format's shape: `name: value`, braces for messages, one line per
// repeated element.

///|
fn make_field(
  number : Int32,
  name : String,
  kind : @reflect.Kind,
  cardinality : @reflect.Cardinality,
  message_type : String?,
  containing : String,
) -> @reflect.FieldDescriptor {
  {
    name,
    full_name: containing + "." + name,
    number,
    kind,
    cardinality,
    json_name: name,
    text_name: name,
    has_presence: false,
    is_extension: false,
    is_map: false,
    packed: true,
    oneof_index: None,
    message_type,
    enum_type: None,
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
test "scalars encode one per line and round-trip" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let s = make_field(2, "s", @reflect.String, @reflect.Optional, None, "test.M")
  let b = make_field(3, "b", @reflect.Bool, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [i, s, b])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(150))
  m.set(s, @reflect.String("hi"))
  m.set(b, @reflect.Bool(true))
  let text = encode(m)
  assert_eq(text, "i: 150\ns: \"hi\"\nb: true\n")
  let back = @dynamic.Message::new(desc)
  decode(text, back)
  assert_eq(back.get(i).int(), 150L)
  assert_eq(back.get(s).string(), "hi")
  assert_eq(back.get(b).bool(), true)
}

///|
test "repeated fields repeat the name" {
  let r = make_field(1, "r", @reflect.Int32, @reflect.Repeated, None, "test.M")
  let desc = message_descriptor("test.M", [r])
  let m = @dynamic.Message::new(desc)
  m.mutable(r).list().append(@reflect.Int32(1))
  m.mutable(r).list().append(@reflect.Int32(2))
  assert_eq(encode(m), "r: 1\nr: 2\n")
  let back = @dynamic.Message::new(desc)
  decode("r: 1 r: 2", back)
  assert_eq(back.get(r).list().length(), 2)
}

///|
test "nested messages use braces" {
  let inner_i = make_field(
    1,
    "i",
    @reflect.Int32,
    @reflect.Optional,
    None,
    "test.Inner",
  )
  let inner_desc = message_descriptor("test.Inner", [inner_i])
  let inner_type = @dynamic.new_message_type(inner_desc)
  @reflect.global_types.register_message(inner_type) catch {
    _ => ()
  }
  let outer = make_field(
    1,
    "inner",
    @reflect.Message,
    @reflect.Optional,
    Some("test.Inner"),
    "test.Outer",
  )
  let desc = message_descriptor("test.Outer", [outer])
  let m = @dynamic.Message::new(desc)
  m.mutable(outer).message().set(inner_i, @reflect.Int32(7))
  let text = encode(m)
  assert_eq(text, "inner {\n  i: 7\n}\n")
  let back = @dynamic.Message::new(desc)
  decode(text, back)
  assert_eq(back.get(outer).message().get(inner_i).int(), 7L)
}

///|
test "comments and colons are optional" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let s = make_field(2, "s", @reflect.String, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [i, s])
  let m = @dynamic.Message::new(desc)
  decode("# a comment\ni: 5\ns \"hi\"\n", m)
  assert_eq(m.get(i).int(), 5L)
  assert_eq(m.get(s).string(), "hi")
}

///|
test "unknown names are refused unless discarded" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  let hit = try {
    decode("nope: 1", m)
    false
  } catch {
    UnknownField(_) => true
    _ => false
  }
  assert_true(hit)
  decode("nope: 1", m, unmarshal_options={
    ..unmarshal_options,
    discard_unknown: true,
  })
}
