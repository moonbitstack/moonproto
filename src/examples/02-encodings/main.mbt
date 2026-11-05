// One reflective message, three encodings. The point is that no encoder knows
// anything about the concrete type: they all walk `reflect.Message`.

///|
const SCHEMA : String = "syntax = \"proto3\";\n" +
  "package report;\n" +
  "message Line {\n" +
  "  string title = 1;\n" +
  "  int64 total = 2;\n" +
  "  bool active = 3;\n" +
  "  repeated string tags = 4;\n" +
  "}\n"

///|
fn main {
  @known.register_all()
  let parsed = @parser.parse("report.proto", SCHEMA) catch {
    _ => abort("bad schema")
  }
  let built = @desc.build_file(parsed) catch { _ => abort("bad descriptor") }
  let descriptor = built.messages[0]
  let message = @dynamic.Message::new(descriptor)

  let title = descriptor.field_by_name("title").unwrap()
  let total = descriptor.field_by_name("total").unwrap()
  let active = descriptor.field_by_name("active").unwrap()
  let tags = descriptor.field_by_name("tags").unwrap()
  message.set(title, @reflect.String("quarterly"))
  message.set(total, @reflect.Int64(10_000_000_000L))
  message.set(active, @reflect.Bool(true))
  message.mutable(tags).list().append(@reflect.String("proto"))

  let binary = @proto.encode(message) catch { _ => abort("binary failed") }
  println("binary: \{binary.length()} bytes")
  let as_json = @json.encode(message) catch { _ => abort("JSON failed") }
  println("json: \{as_json}")
  let as_text = @text.encode(message) catch { _ => abort("text failed") }
  println("text: \{as_text}")

  // Each format parses back into a fresh message of the same descriptor.
  let from_json = @dynamic.Message::new(descriptor)
  @json.decode(as_json, from_json) catch {
    _ => abort("JSON decode failed")
  }
  println("total from JSON: \{from_json.get(total).int()}")
  let from_text = @dynamic.Message::new(descriptor)
  @text.decode(as_text, from_text) catch {
    _ => abort("text decode failed")
  }
  println("title from text: \{from_text.get(title).string()}")
  let from_binary = @dynamic.Message::new(descriptor)
  @proto.decode(binary, from_binary) catch {
    _ => abort("binary decode failed")
  }
  let agree = @proto.equal(from_json, from_binary) &&
    @proto.equal(from_text, from_binary)
  println("all three agree: \{agree}")
}
