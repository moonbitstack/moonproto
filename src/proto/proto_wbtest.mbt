// End-to-end binary tests over a hand-built descriptor. The expected bytes are
// the encodings the format fixes.

///|
fn make_field(
  number : Int32,
  name : String,
  kind : @reflect.Kind,
  cardinality : @reflect.Cardinality,
  packed : Bool,
  is_map : Bool,
  message_type : String?,
  map_key_field : @reflect.FieldDescriptor?,
  map_value_field : @reflect.FieldDescriptor?,
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
    is_map,
    packed,
    oneof_index: None,
    message_type,
    enum_type: None,
    has_default: false,
    default_value: @reflect.Invalid,
    default_enum_name: None,
    containing_message: containing,
    map_key_field,
    map_value_field,
  }
}

///|
fn scalar_field(
  number : Int32,
  name : String,
  kind : @reflect.Kind,
) -> @reflect.FieldDescriptor {
  make_field(
    number,
    name,
    kind,
    @reflect.Optional,
    false,
    false,
    None,
    None,
    None,
    "test.Scalars",
  )
}

///|
fn repeated_field(
  number : Int32,
  name : String,
  kind : @reflect.Kind,
  packed : Bool,
) -> @reflect.FieldDescriptor {
  make_field(
    number,
    name,
    kind,
    @reflect.Repeated,
    packed,
    false,
    None,
    None,
    None,
    "test.Scalars",
  )
}

///|
fn message_field(
  number : Int32,
  name : String,
  message_type : String,
) -> @reflect.FieldDescriptor {
  make_field(
    number,
    name,
    @reflect.Message,
    @reflect.Optional,
    false,
    false,
    Some(message_type),
    None,
    None,
    "test.Scalars",
  )
}

///|
fn message_descriptor(
  full_name : String,
  fields : Array[@reflect.FieldDescriptor],
) -> @reflect.MessageDescriptor {
  {
    name: "Scalars",
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
test "scalars encode to the fixed bytes and round-trip" {
  let i = scalar_field(1, "i", @reflect.Int32)
  let s = scalar_field(2, "s", @reflect.String)
  let b = scalar_field(3, "b", @reflect.Bool)
  let desc = message_descriptor("test.Scalars", [i, s, b])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(150))
  m.set(s, @reflect.String("hi"))
  m.set(b, @reflect.Bool(true))
  let bytes = encode(m)
  assert_eq(bytes, b"\x08\x96\x01\x12\x02hi\x18\x01")
  assert_eq(size(m), 9)
  let back = @dynamic.Message::new(desc)
  decode(bytes, back)
  assert_eq(back.get(i).int(), 150L)
  assert_eq(back.get(s).string(), "hi")
  assert_eq(back.get(b).bool(), true)
  assert_true(equal(m, back))
}

///|
test "negative int32 sign-extends to ten octets" {
  let i = scalar_field(1, "i", @reflect.Int32)
  let desc = message_descriptor("test.Scalars", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(-1))
  let bytes = encode(m)
  assert_eq(bytes, b"\x08\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01")
  let back = @dynamic.Message::new(desc)
  decode(bytes, back)
  assert_eq(back.get(i).int(), -1L)
}

///|
test "packed repeated int32 uses one length-delimited field" {
  let r = repeated_field(4, "r", @reflect.Int32, true)
  let desc = message_descriptor("test.Scalars", [r])
  let m = @dynamic.Message::new(desc)
  let list = m.mutable(r).list()
  list.append(@reflect.Int32(1))
  list.append(@reflect.Int32(300))
  let bytes = encode(m)
  assert_eq(bytes, b"\x22\x03\x01\xac\x02")
  assert_eq(size(m), 5)
  let back = @dynamic.Message::new(desc)
  decode(bytes, back)
  let got = back.get(r).list()
  assert_eq(got.length(), 2)
  assert_eq(got.get(0).int(), 1L)
  assert_eq(got.get(1).int(), 300L)
}

///|
test "expanded repeated int32 repeats the tag" {
  let r = repeated_field(4, "r", @reflect.Int32, false)
  let desc = message_descriptor("test.Scalars", [r])
  let m = @dynamic.Message::new(desc)
  let list = m.mutable(r).list()
  list.append(@reflect.Int32(1))
  list.append(@reflect.Int32(300))
  assert_eq(encode(m), b"\x20\x01\x20\xac\x02")
}

///|
test "zig-zag and fixed widths" {
  let sint = scalar_field(1, "z", @reflect.Sint32)
  let fixed = scalar_field(2, "f", @reflect.Fixed32)
  let desc = message_descriptor("test.Scalars", [sint, fixed])
  let m = @dynamic.Message::new(desc)
  m.set(sint, @reflect.Int32(-2))
  m.set(fixed, @reflect.Uint32(0x1234_5678U))
  assert_eq(encode(m), b"\x08\x03\x15\x78\x56\x34\x12")
  let back = @dynamic.Message::new(desc)
  decode(encode(m), back)
  assert_eq(back.get(sint).int(), -2L)
  assert_eq(back.get(fixed).uint(), 0x1234_5678UL)
}

///|
test "unknown fields survive a round-trip" {
  let i = scalar_field(1, "i", @reflect.Int32)
  let desc = message_descriptor("test.Scalars", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(1))
  // Field 9 is not in the descriptor, so it lands in the unknown set.
  let extra = b"\x48\x07"
  let bytes = encode(m) + extra
  let back = @dynamic.Message::new(desc)
  decode(bytes, back)
  assert_eq(back.get(i).int(), 1L)
  assert_eq(back.get_unknown().bytes(), extra)
  assert_eq(encode(back), bytes)
}

///|
test "map fields encode as repeated entries and round-trip" {
  let key = make_field(
    1,
    "key",
    @reflect.String,
    @reflect.Optional,
    false,
    false,
    None,
    None,
    None,
    "test.Scalars.MEntry",
  )
  let value = make_field(
    2,
    "value",
    @reflect.Int32,
    @reflect.Optional,
    false,
    false,
    None,
    None,
    None,
    "test.Scalars.MEntry",
  )
  let entry_desc = message_descriptor("test.Scalars.MEntry", [key, value])
  let map_field = make_field(
    3,
    "m",
    @reflect.Message,
    @reflect.Repeated,
    false,
    true,
    Some("test.Scalars.MEntry"),
    Some(key),
    Some(value),
    "test.Scalars",
  )
  let desc = message_descriptor("test.Scalars", [map_field])
  let _ = entry_desc
  let m = @dynamic.Message::new(desc)
  let map = m.mutable(map_field).map()
  map.set(@reflect.String("a"), @reflect.Int32(1))
  map.set(@reflect.String("b"), @reflect.Int32(2))
  let back = @dynamic.Message::new(desc)
  decode(encode(m), back)
  let got = back.get(map_field).map()
  assert_eq(got.length(), 2)
  assert_eq(got.get(@reflect.String("a")).int(), 1L)
  assert_eq(got.get(@reflect.String("b")).int(), 2L)
}

///|
test "nested messages round-trip through the global type registry" {
  let inner_i = scalar_field(1, "i", @reflect.Int32)
  let inner_desc = message_descriptor("test.Inner", [inner_i])
  let inner_type = @dynamic.new_message_type(inner_desc)
  @reflect.global_types.register_message(inner_type) catch {
    _ => ()
  }
  let outer_field = message_field(1, "inner", "test.Inner")
  let outer_desc = message_descriptor("test.Outer", [outer_field])
  let outer = @dynamic.Message::new(outer_desc)
  let inner = outer.mutable(outer_field).message()
  inner.set(inner_i, @reflect.Int32(7))
  let bytes = encode(outer)
  let back = @dynamic.Message::new(outer_desc)
  decode(bytes, back)
  assert_eq(back.get(outer_field).message().get(inner_i).int(), 7L)
}

// -- extensions --------------------------------------------------------------

///|
fn extension_field(number : Int32, name : String) -> @reflect.FieldDescriptor {
  {
    ..make_field(
      number,
      name,
      @reflect.Int32,
      @reflect.Optional,
      false,
      false,
      None,
      None,
      None,
      "test.Ext",
    ),
    full_name: "test." + name,
    is_extension: true,
  }
}

///|
fn extension_descriptor() -> @reflect.MessageDescriptor {
  {
    name: "Ext",
    full_name: "test.Ext",
    syntax: @reflect.Proto2,
    fields: [],
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
test "an extension is written to the wire and read back" {
  let desc = extension_descriptor()
  let ext = extension_field(100, "my_ext")
  let extension_type = @dynamic.new_extension_type(ext)
  @reflect.global_types.register_extension(extension_type) catch {
    _ => ()
  }
  let m = @dynamic.Message::new(desc)
  set_extension(m, extension_type, @reflect.Int32(42))
  assert_true(has_extension(m, extension_type))
  let bytes = encode(m)
  // Field 100, varint: tag a0 06, value 2a.
  assert_eq(bytes, b"\xa0\x06\x2a")
  assert_eq(size(m), 3)
  let back = @dynamic.Message::new(desc)
  decode(bytes, back)
  assert_true(has_extension(back, extension_type))
  match get_extension(back, extension_type) {
    Some(value) => assert_eq(value.int(), 42L)
    None => abort("extension dropped on decode")
  }
  assert_eq(back.get_unknown().bytes().length(), 0)
  assert_eq(encode(back), bytes)
}

///|
test "range_extensions reports each extension once" {
  let desc = extension_descriptor()
  let ext = extension_field(100, "my_ext")
  let extension_type = @dynamic.new_extension_type(ext)
  @reflect.global_types.register_extension(extension_type) catch {
    _ => ()
  }
  let m = @dynamic.Message::new(desc)
  set_extension(m, extension_type, @reflect.Int32(1))
  set_extension(m, extension_type, @reflect.Int32(2))
  let seen : Array[Int32] = []
  let values : Array[Int64] = []
  range_extensions(m, fn(item, value) {
    seen.push(item.descriptor().number)
    values.push(value.int())
    true
  })
  assert_eq(seen.length(), 1)
  assert_eq(seen[0], 100)
  assert_eq(values[0], 2L)
}

///|
test "merge, clone and equal see extensions" {
  let desc = extension_descriptor()
  let ext = extension_field(100, "my_ext")
  let extension_type = @dynamic.new_extension_type(ext)
  @reflect.global_types.register_extension(extension_type) catch {
    _ => ()
  }
  let a = @dynamic.Message::new(desc)
  set_extension(a, extension_type, @reflect.Int32(1))
  let b = @dynamic.Message::new(desc)
  merge(b, a)
  assert_true(has_extension(b, extension_type))
  assert_true(equal(a, b))
  let copy = clone(b)
  assert_true(equal(b, copy))
  set_extension(b, extension_type, @reflect.Int32(2))
  assert_true(!equal(a, b))
}

///|
fn required_descriptor() -> @reflect.MessageDescriptor {
  let source = "syntax = \"proto2\";\npackage r;\nmessage P { required int32 must = 1; }\n"
  let file = @parser.parse("r.proto", source) catch {
    _ => abort("parse failed")
  }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  @reflect.global_types.register_message(
    @dynamic.new_message_type(built.messages[0]),
  ) catch {
    _ => ()
  }
  built.messages[0]
}

///|
test "a missing required field is refused, and allow_partial lets it through" {
  let message = @dynamic.Message::new(required_descriptor())
  let refused = try {
    let _ = encode(message)
    false
  } catch {
    Required(_) => true
    _ => false
  }
  assert_true(refused)
  let bytes = encode(message, marshal_options={
    ..marshal_options,
    allow_partial: true,
  }) catch {
    _ => abort("allow_partial still refused")
  }
  assert_eq(bytes.length(), 0)
  let decoded = @dynamic.Message::new(required_descriptor())
  let decode_refused = try {
    decode(b"", decoded)
    false
  } catch {
    Required(_) => true
    _ => false
  }
  assert_true(decode_refused)
}
