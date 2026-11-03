// Size-delimited framing: one varint length, then the message bytes, twice.

///|
fn make_field(
  number : Int32,
  name : String,
  kind : @reflect.Kind,
) -> @reflect.FieldDescriptor {
  {
    name,
    full_name: "test.M." + name,
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
    enum_type: None,
    has_default: false,
    default_value: @reflect.Invalid,
    default_enum_name: None,
    containing_message: "test.M",
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
test "two messages round-trip through the framing" {
  let i = make_field(1, "i", @reflect.Int32)
  let desc = message_descriptor("test.M", [i])
  let first = @dynamic.Message::new(desc)
  first.set(i, @reflect.Int32(150))
  let second = @dynamic.Message::new(desc)
  second.set(i, @reflect.Int32(7))
  let writer = BytesWriter::new()
  let written = encode_to(writer, first) + encode_to(writer, second)
  let bytes = writer.to_bytes()
  assert_eq(written, bytes.length())
  // 03 08 96 01 | 02 08 07
  assert_eq(bytes, b"\x03\x08\x96\x01\x02\x08\x07")
  let reader = BytesReader::new(bytes)
  let back_first = @dynamic.Message::new(desc)
  let back_second = @dynamic.Message::new(desc)
  decode_from(reader, back_first)
  decode_from(reader, back_second)
  assert_eq(back_first.get(i).int(), 150L)
  assert_eq(back_second.get(i).int(), 7L)
}

///|
test "a size above the ceiling is refused" {
  let i = make_field(1, "i", @reflect.Int32)
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(1))
  let writer = BytesWriter::new()
  let _ = encode_to(writer, m)
  let reader = BytesReader::new(writer.to_bytes())
  let hit = try {
    decode_from(reader, @dynamic.Message::new(desc), unmarshal_options={
      ..unmarshal_options,
      max_size: 1,
    })
    false
  } catch {
    Size(_, _) => true
    _ => false
  }
  assert_true(hit)
}
