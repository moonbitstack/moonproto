// The MoonBit side of the protoc-gen-go interop check. Both programs read the
// same tests/interop/interop.proto and the same tests/interop/fixture.txt;
// each must produce the same bytes, and each must be able to read the other's
// bytes back and recover every field.

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
/// `protoc --encode` of the fixture, and the bytes `protoc-gen-go` emits.
const PROTOC_BYTES : Bytes = b"\x08\x96\x01\x10\x80\xc8\xaf\xa0\x25\x18\x07\x20\x08\x28\x01\x30\x03\x3d\x00\x00\x80\x3f\x41\x00\x00\x00\x00\x00\x00\xf0\x3f\x4d\xfd\xff\xff\xff\x51\xfc\xff\xff\xff\xff\xff\xff\xff\x5d\x00\x00\x20\x40\x61\x00\x00\x00\x00\x00\x00\x0c\x40\x68\x01\x72\x02\x68\x69\x7a\x02\x01\x02\x82\x01\x03\x01\xac\x02\x8a\x01\x01\x61\x8a\x01\x01\x62\x92\x01\x05\x0a\x01\x6b\x10\x05\x9a\x01\x02\x08\x09\xa0\x01\x01\xb2\x01\x01\x78"

///|
async fn main {
  let args = @env.args()
  let mode = if args.length() > 1 { args[args.length() - 1] } else { "" }
  let input = read_input()
  let descriptor = interop_descriptor()
  let bytes = if mode == "encode" {
    let message = @dynamic.Message::new(descriptor)
    @text.decode(input, message) catch {
      err => fail("text decode failed: " + err.to_string())
    }
    encode_checked(message)
  } else if mode == "decode" {
    let message = @dynamic.Message::new(descriptor)
    let bytes = @base16.decode(trim(input)) catch {
      _ => fail("input is not hex")
    }
    @proto.decode(bytes, message) catch {
      err => fail("binary decode failed: " + err.to_string())
    }
    encode_checked(message)
  } else {
    fail("usage: interop-mbt encode|decode")
  }
  write_out(@base16.encode(bytes[:]) + "\n")
}

///|
/// Re-encoding to the fixture bytes asserts every field of the decoded
/// message at once: a single wrong scalar, list element, map entry or oneof
/// choice changes the output.
fn encode_checked(message : @dynamic.Message) -> Bytes {
  let bytes = @proto.encode(message) catch {
    err => fail("binary encode failed: " + err.to_string())
  }
  if bytes != PROTOC_BYTES {
    fail("decoded values do not match the interop fixture")
  }
  bytes
}

///|
fn interop_descriptor() -> @reflect.MessageDescriptor {
  let file = @parser.parse("interop.proto", INTEROP_SOURCE) catch {
    _ => fail("could not parse interop.proto")
  }
  let built = @desc.build_file(file) catch {
    _ => fail("could not build the interop descriptor")
  }
  // The text format resolves enum names through the file registry.
  @reflect.global_files.register(built) catch {
    _ => ()
  }
  register_tree(built.messages)
  for message in built.messages {
    if message.full_name == "interop.All" {
      return message
    }
  }
  fail("missing interop.All")
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
async fn read_input() -> String {
  let buf = Buffer()
  while true {
    match @stdio.stdin.read_some() {
      Some(chunk) => buf.write_bytes(chunk)
      None => break
    }
  }
  @utf8.decode(buf.to_bytes()) catch {
    _ => fail("input is not UTF-8")
  }
}

///|
async fn write_out(text : String) -> Unit {
  let bytes = @utf8.encode(text)
  let mut written = 0
  while written < bytes.length() {
    let count = @stdio.stdout.write_once(
      bytes,
      offset=written,
      len=bytes.length() - written,
    )
    if count <= 0 {
      break
    }
    written = written + count
  }
}

///|
fn[T] fail(message : String) -> T {
  abort("interop-mbt: " + message)
}

///|
fn trim(text : String) -> String {
  let mut start = 0
  let mut end = text.length()
  while start < end && is_space(text[start]) {
    start = start + 1
  }
  while end > start && is_space(text[end - 1]) {
    end = end - 1
  }
  text[start:end].to_owned()
}

///|
/// A `String` index is a UTF-16 code unit, so the trim works on integer code
/// units instead of bytes. The fixture is ASCII.
fn is_space(code : UInt16) -> Bool {
  let n = code.to_int()
  n == 32 || n == 10 || n == 13 || n == 9
}
