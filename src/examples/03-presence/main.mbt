// Presence decides what "set" means, and the wire is where the difference
// shows: a field with presence keeps an explicit zero, and one without it
// cannot. Three ways to write a zero, one rule: it is on the wire only where
// the schema gives it presence.

///|
const SCHEMA : String = "syntax = \"proto3\";\n" +
  "package presence;\n" +
  "message Probe {\n" +
  "  int32 count = 1;\n" +
  "  string label = 2;\n" +
  "  optional int32 limit = 3;\n" +
  "  double ratio = 4;\n" +
  "}\n"

///|
fn main {
  let parsed = @parser.parse("presence.proto", SCHEMA) catch {
    _ => abort("bad schema")
  }
  let built = @desc.build_file(parsed) catch { _ => abort("bad descriptor") }
  let descriptor = built.messages[0]
  let message = @dynamic.Message::new(descriptor)
  let count = descriptor.field_by_name("count").unwrap()
  let label = descriptor.field_by_name("label").unwrap()
  let limit = descriptor.field_by_name("limit").unwrap()
  let ratio = descriptor.field_by_name("ratio").unwrap()

  message.set(count, @reflect.Int32(0))
  message.set(label, @reflect.String(""))
  let zeroed = @proto.encode(message) catch { _ => abort("encode failed") }
  println("implicit zeros: \{zeroed.length()} bytes")
  let zeroed_json = @json.encode(message) catch { _ => abort("JSON failed") }
  println("implicit zeros in JSON: \{zeroed_json}")

  // The `optional` field has presence, so its zero is a value the reader keeps.
  message.set(limit, @reflect.Int32(0))
  let with_limit = @proto.encode(message) catch { _ => abort("encode failed") }
  println("optional zero: \{with_limit.length()} bytes")
  let with_limit_json = @json.encode(message) catch {
    _ => abort("JSON failed")
  }
  println("optional zero in JSON: \{with_limit_json}")

  // Negative zero is not the zero: the sign bit is part of the value.
  message.set(ratio, @reflect.Double(-0.0))
  let with_ratio = @proto.encode(message) catch { _ => abort("encode failed") }
  println("negative zero: \{with_ratio.length()} bytes")
  let with_ratio_json = @json.encode(message) catch {
    _ => abort("JSON failed")
  }
  println("negative zero in JSON: \{with_ratio_json}")

  // A sender may still write an explicit zero; reading it back does not make it
  // a value, so the next encode drops it again.
  let read = @dynamic.Message::new(descriptor)
  @proto.decode(b"\x08\x00", read) catch {
    _ => abort("decode failed")
  }
  println("count read back: \{read.get(count).int()}")
  println("count has a value: \{read.has(count)}")
  let re_encoded = @proto.encode(read) catch { _ => abort("encode failed") }
  println("re-encoded: \{re_encoded.length()} bytes")
}
