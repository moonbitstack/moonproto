// The playground's engine: one entry point, a sample name in and a JSON object
// out, so the page's script knows nothing about MoonBit values.

///|
const SCHEMA : String = "syntax = \"proto3\";\n" +
  "package demo;\n" +
  "\n" +
  "enum Color {\n" +
  "  RED  = 0;\n" +
  "  BLUE = 1;\n" +
  "}\n" +
  "\n" +
  "message Envelope {\n" +
  "  int32  id     = 1;\n" +
  "  string name   = 2;\n" +
  "  map<string, int32> counts = 3;\n" +
  "  Color  color  = 4;\n" +
  "}\n"

///|
fn nibble(value : Int32) -> Char {
  if value < 10 {
    (48 + value).unsafe_to_char()
  } else {
    (87 + value).unsafe_to_char()
  }
}

///|
fn hex(bytes : Bytes) -> String {
  let out = StringBuilder()
  for i, byte in bytes {
    if i > 0 {
      out.write_char(' ')
    }
    let code = byte.to_int()
    out.write_char(nibble(code / 16))
    out.write_char(nibble(code % 16))
  }
  out.to_string()
}

///|
/// One message, three encodings. `name` is `full`, `unicode` or `empty`; an
/// unknown name is read as `empty`.
pub fn sample(name : String) -> String {
  let parsed = @parser.parse("envelope.proto", SCHEMA) catch {
    _ => abort("the pinned schema no longer parses")
  }
  let file = @desc.build_file(parsed) catch {
    _ => abort("the pinned schema no longer builds")
  }
  // Enum names in JSON and text are resolved through the file registry.
  @reflect.global_files.register(file) catch {
    _ => ()
  }
  let descriptor = file.messages[0]
  let message = @dynamic.Message::new(descriptor)
  let id = descriptor.field_by_name("id").unwrap()
  let field_name = descriptor.field_by_name("name").unwrap()
  let counts = descriptor.field_by_name("counts").unwrap()
  let color = descriptor.field_by_name("color").unwrap()
  match name {
    "full" => {
      message.set(id, @reflect.Int32(42))
      message.set(field_name, @reflect.String("moon"))
      message.mutable(counts).map().set(@reflect.String("a"), @reflect.Int32(1))
      message.set(color, @reflect.Enum(1))
    }
    "unicode" => {
      message.set(id, @reflect.Int32(7))
      message.set(field_name, @reflect.String("月"))
      message.mutable(counts).map().set(@reflect.String("b"), @reflect.Int32(2))
      message.set(color, @reflect.Enum(1))
    }
    _ => ()
  }
  let bytes = @proto.encode(message) catch { _ => abort("encode failed") }
  let as_json = @json.encode(message) catch { _ => abort("JSON failed") }
  let as_text = @text.encode(message) catch { _ => abort("text failed") }
  let result : @cjson.Json = {
    "length": @cjson.Json::number(bytes.length().to_double()),
    "bytes": @cjson.Json::string(hex(bytes)),
    "json": @cjson.Json::string(as_json),
    "text": @cjson.Json::string(as_text),
  }
  result.stringify()
}
