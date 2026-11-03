// Cross-implementation check: the same .proto and the same values, encoded by
// protoc 36.2 and by this package, must be the same bytes.
//
// The reference bytes below were produced with:
//   protoc --encode=interop.All -I . interop.proto < fixture.txt
// for the fixture in tests/interop/interop.proto.

///|
const INTEROP_SOURCE : String = "syntax = \"proto3\";\n" +
  "package interop;\n" +
  "enum Color { RED = 0; BLUE = 1; }\n" +
  "message Inner { int32 x = 1; }\n" +
  "message All {\n" +
  "  int32 i32 = 1;\n" +
  "  int64 i64 = 2;\n" +
  "  uint32 u32 = 3;\n" +
  "  uint64 u64 = 4;\n" +
  "  sint32 s32 = 5;\n" +
  "  sint64 s64 = 6;\n" +
  "  fixed32 f32 = 7;\n" +
  "  fixed64 f64 = 8;\n" +
  "  sfixed32 sf32 = 9;\n" +
  "  sfixed64 sf64 = 10;\n" +
  "  float flt = 11;\n" +
  "  double dbl = 12;\n" +
  "  bool flag = 13;\n" +
  "  string text = 14;\n" +
  "  bytes blob = 15;\n" +
  "  repeated int32 nums = 16;\n" +
  "  repeated string names = 17;\n" +
  "  map<string, int32> counts = 18;\n" +
  "  Inner inner = 19;\n" +
  "  Color color = 20;\n" +
  "  oneof pick { int32 pick_i = 21; string pick_s = 22; }\n" +
  "}\n"

///|
const PROTOC_BYTES : Bytes = b"\x08\x96\x01\x10\x80\xc8\xaf\xa0\x25\x18\x07\x20\x08\x28\x01\x30\x03\x3d\x00\x00\x80\x3f\x41\x00\x00\x00\x00\x00\x00\xf0\x3f\x4d\xfd\xff\xff\xff\x51\xfc\xff\xff\xff\xff\xff\xff\xff\x5d\x00\x00\x20\x40\x61\x00\x00\x00\x00\x00\x00\x0c\x40\x68\x01\x72\x02\x68\x69\x7a\x02\x01\x02\x82\x01\x03\x01\xac\x02\x8a\x01\x01\x61\x8a\x01\x01\x62\x92\x01\x05\x0a\x01\x6b\x10\x05\x9a\x01\x02\x08\x09\xa0\x01\x01\xb2\x01\x01\x78"

///|
fn interop_descriptor() -> @reflect.MessageDescriptor {
  let file = @parser.parse("interop.proto", INTEROP_SOURCE) catch {
    _ => abort("parse failed")
  }
  let built = @desc.build_file(file) catch { _ => abort("build failed") }
  register_tree(built.messages)
  for message in built.messages {
    if message.full_name == "interop.All" {
      return message
    }
  }
  abort("missing interop.All")
}

///|
fn register_tree(messages : Array[@reflect.MessageDescriptor]) -> Unit {
  for message in messages {
    @reflect.global_types.register_message(@dynamic.new_message_type(message)) catch {
      _ => ()
    }
    register_tree(message.nested_messages)
  }
}

///|
fn field_of(
  message : &@reflect.Message,
  name : String,
) -> @reflect.FieldDescriptor {
  match message.descriptor().field_by_name(name) {
    Some(field) => field
    None => abort("missing field " + name)
  }
}

///|
fn fill(message : &@reflect.Message) -> Unit {
  message.set(field_of(message, "i32"), @reflect.Int32(150))
  message.set(field_of(message, "i64"), @reflect.Int64(10_000_000_000L))
  message.set(field_of(message, "u32"), @reflect.Uint32(7U))
  message.set(field_of(message, "u64"), @reflect.Uint64(8UL))
  message.set(field_of(message, "s32"), @reflect.Int32(-1))
  message.set(field_of(message, "s64"), @reflect.Int64(-2L))
  message.set(field_of(message, "f32"), @reflect.Uint32(0x3F80_0000U))
  message.set(
    field_of(message, "f64"),
    @reflect.Uint64(0x3FF0_0000_0000_0000UL),
  )
  message.set(field_of(message, "sf32"), @reflect.Int32(-3))
  message.set(field_of(message, "sf64"), @reflect.Int64(-4L))
  message.set(
    field_of(message, "flt"),
    @reflect.Float(@float.Float::from_double(2.5)),
  )
  message.set(field_of(message, "dbl"), @reflect.Double(3.5))
  message.set(field_of(message, "flag"), @reflect.Bool(true))
  message.set(field_of(message, "text"), @reflect.String("hi"))
  message.set(field_of(message, "blob"), @reflect.Bytes(b"\x01\x02"))
  let nums = message.mutable(field_of(message, "nums")).list()
  nums.append(@reflect.Int32(1))
  nums.append(@reflect.Int32(300))
  let names = message.mutable(field_of(message, "names")).list()
  names.append(@reflect.String("a"))
  names.append(@reflect.String("b"))
  let counts = message.mutable(field_of(message, "counts")).map()
  counts.set(@reflect.String("k"), @reflect.Int32(5))
  let inner = message.mutable(field_of(message, "inner")).message()
  inner.set(field_of(inner, "x"), @reflect.Int32(9))
  message.set(field_of(message, "color"), @reflect.Enum(1))
  message.set(field_of(message, "pick_s"), @reflect.String("x"))
}

///|
test "our encoding of the fixture matches protoc's byte for byte" {
  let desc = interop_descriptor()
  let message = @dynamic.Message::new(desc)
  fill(message)
  let ours = encode(message) catch {
    err => abort("encode failed: " + err.to_string())
  }
  assert_eq(ours, PROTOC_BYTES)
  assert_eq(size(message), PROTOC_BYTES.length())
}

///|
test "protoc's bytes decode to the same values and re-encode" {
  let desc = interop_descriptor()
  let message = @dynamic.Message::new(desc)
  decode(PROTOC_BYTES, message) catch {
    err => abort("decode failed: " + err.to_string())
  }
  assert_eq(message.get(field_of(message, "i32")).int(), 150L)
  assert_eq(message.get(field_of(message, "i64")).int(), 10_000_000_000L)
  assert_eq(message.get(field_of(message, "s32")).int(), -1L)
  assert_eq(message.get(field_of(message, "sf64")).int(), -4L)
  assert_eq(message.get(field_of(message, "dbl")).float(), 3.5)
  assert_eq(message.get(field_of(message, "text")).string(), "hi")
  assert_eq(message.get(field_of(message, "blob")).bytes(), b"\x01\x02")
  assert_eq(message.get(field_of(message, "nums")).list().length(), 2)
  assert_eq(message.get(field_of(message, "counts")).map().length(), 1)
  assert_eq(message.get(field_of(message, "color")).enum_number(), 1)
  assert_eq(message.get(field_of(message, "pick_s")).string(), "x")
  assert_eq(encode(message), PROTOC_BYTES)
}
