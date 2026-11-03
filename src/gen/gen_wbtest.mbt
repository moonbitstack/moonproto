// The generator end to end: source in, request bytes, generated files out.

///|
const SOURCE : String = "syntax = \"proto3\";\n" +
  "package test;\n" +
  "message M { int32 i = 1; string s = 2; repeated int32 nums = 3; }\n"

///|
test "generated source has a struct, accessors and a descriptor" {
  let file = @parser.parse("test.proto", SOURCE) catch {
    _ => abort("parse failed")
  }
  let source = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(source.contains("pub struct M"))
  assert_true(source.contains("pub fn M::i"))
  assert_true(source.contains("pub fn M::set_i"))
  assert_true(source.contains("pub fn M::nums"))
  assert_true(source.contains("pub fn file_descriptor"))
  assert_true(source.contains("@desc.build_file"))
}

///|
test "the plugin turns a request into a response with one file" {
  let file = @parser.parse("test.proto", SOURCE) catch {
    _ => abort("parse failed")
  }
  let request : Request = {
    files_to_generate: ["test.proto"],
    parameter: "",
    proto_file: [file],
  }
  let request_bytes = encode_request(request) catch {
    _ => abort("encode request failed")
  }
  let response_bytes = plugin_main(request_bytes)
  let (files, error) = decode_response(response_bytes) catch {
    _ => abort("decode response failed")
  }
  assert_true(error is None)
  assert_eq(files.length(), 1)
  assert_eq(files[0].0, "test.mbt")
  assert_true(files[0].1.contains("pub struct M"))
}

///|
test "a file that is not requested produces no output" {
  let file = @parser.parse("test.proto", SOURCE) catch {
    _ => abort("parse failed")
  }
  let request : Request = {
    files_to_generate: [],
    parameter: "",
    proto_file: [file],
  }
  let response_bytes = plugin_main(
    encode_request(request) catch {
      _ => abort("encode failed")
    },
  )
  let (files, error) = decode_response(response_bytes) catch {
    _ => abort("decode failed")
  }
  assert_true(error is None)
  assert_eq(files.length(), 0)
}

///|
test "enums generate code and of" {
  let source = "syntax = \"proto3\";\npackage e;\nenum Color { RED = 0; BLUE = 1; }\n"
  let file = @parser.parse("e.proto", source) catch {
    _ => abort("parse failed")
  }
  let generated = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(generated.contains("pub(all) enum Color"))
  assert_true(generated.contains("pub fn Color::code"))
  assert_true(generated.contains("Unknown(n)"))
}

///|
test "the response alone round-trips" {
  let bytes = encode_response([("a.mbt", "hello")], None) catch {
    err => {
      println("encode_response: " + err.to_string())
      abort("encode_response failed")
    }
  }
  let (files, error) = decode_response(bytes) catch {
    err => {
      println("decode_response: " + err.to_string())
      abort("decode_response failed")
    }
  }
  assert_true(error is None)
  assert_eq(files.length(), 1)
  assert_eq(files[0].0, "a.mbt")
  assert_eq(files[0].1, "hello")
}

///|
test "the request alone round-trips" {
  let file = @parser.parse("test.proto", SOURCE) catch {
    _ => abort("parse failed")
  }
  let request : Request = {
    files_to_generate: ["test.proto"],
    parameter: "",
    proto_file: [file],
  }
  let bytes = encode_request(request) catch {
    _ => abort("encode_request failed")
  }
  let back = decode_request(bytes) catch { _ => abort("decode_request failed") }
  assert_eq(back.files_to_generate.length(), 1)
  assert_eq(back.proto_file.length(), 1)
  assert_eq(back.proto_file[0].name, "test.proto")
}

///|
test "plugin types are registered" {
  assert_true(plugin_types.num_messages() > 0)
}

///|
test "a oneof gets an enum, a reader and a writer" {
  let source = "syntax = \"proto3\";\npackage o;\nmessage M { oneof pick { int32 a = 1; string b = 2; } }\n"
  let file = @parser.parse("o.proto", source) catch {
    _ => abort("parse failed")
  }
  let generated = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(generated.contains("pub(all) enum M_Pick"))
  assert_true(generated.contains("A(Int32)"))
  assert_true(generated.contains("B(String)"))
  assert_true(generated.contains("NoPick"))
  assert_true(generated.contains("pub fn M::pick(self : M) -> M_Pick"))
  assert_true(
    generated.contains("pub fn M::set_pick(self : M, value : M_Pick)"),
  )
}

///|
test "every message gets JSON in and out" {
  let file = @parser.parse("test.proto", SOURCE) catch {
    _ => abort("parse failed")
  }
  let generated = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(
    generated.contains(
      "pub fn M::to_json(self : M) -> String raise @json.Refused",
    ),
  )
  assert_true(
    generated.contains(
      "pub fn M::from_json(text : String) -> M raise @json.Refused",
    ),
  )
}

///|
test "a field the reflective contract already names gets a suffix" {
  let source = "syntax = \"proto3\";\npackage k;\nmessage M { string type = 1; int32 message_type = 2; }\n"
  let file = @parser.parse("k.proto", source) catch {
    _ => abort("parse failed")
  }
  let generated = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(generated.contains("pub fn M::type_(self : M)"))
  assert_true(generated.contains("pub fn M::message_type_field(self : M)"))
  // The descriptor still carries the proto name.
  assert_true(generated.contains("name: \"message_type\""))
}

///|
test "editions features survive into the generated descriptor" {
  let source = "edition = \"2023\";\npackage e;\noption features.field_presence = IMPLICIT;\nmessage M { int32 a = 1; }\n"
  let file = @parser.parse("e.proto", source) catch {
    _ => abort("parse failed")
  }
  let generated = generate_source(file) catch { _ => abort("generate failed") }
  assert_true(generated.contains("edition: Some(\"2023\")"))
  assert_true(generated.contains("field_presence: 2"))
}
