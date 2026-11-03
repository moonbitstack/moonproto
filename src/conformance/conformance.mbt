// The conformance harness: request descriptors, a rich test message, and the
// handler that reads one format and writes another.

///|
fn f(
  name : String,
  number : Int32,
  label : Int32,
  type_code : Int32,
  type_name : String?,
  oneof_index : Int32?,
) -> @desc.FieldDescriptorProto {
  {
    name,
    number,
    label,
    type_code,
    type_name,
    json_name: None,
    default_value: None,
    oneof_index,
    proto3_optional: false,
    packed_off: false,
  }
}

///|
fn m(
  name : String,
  fields : Array[@desc.FieldDescriptorProto],
  nested : Array[@desc.DescriptorProto],
  enums : Array[@desc.EnumDescriptorProto],
  oneofs : Array[@desc.OneofDescriptorProto],
  map_entry : Bool,
) -> @desc.DescriptorProto {
  {
    name,
    field: fields,
    nested_type: nested,
    enum_type: enums,
    extension: [],
    oneof_decl: oneofs,
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry,
  }
}

///|
fn request_descriptor() -> @desc.FileDescriptorProto {
  let request = m(
    "ConformanceRequest",
    [
      f("protobuf_payload", 1, 1, 12, None, None),
      f("json_payload", 2, 1, 9, None, None),
      f(
        "requested_output_format",
        3,
        1,
        14,
        Some(".conformance.WireFormat"),
        None,
      ),
      f("message_type", 4, 1, 9, None, None),
      f("test_category", 5, 1, 14, Some(".conformance.TestCategory"), None),
      f("print_unknown_fields", 7, 1, 8, None, None),
      f("text_payload", 8, 1, 9, None, None),
    ],
    [],
    [],
    [],
    false,
  )
  let response = m(
    "ConformanceResponse",
    [
      f("parse_error", 1, 1, 9, None, None),
      f("runtime_error", 2, 1, 9, None, None),
      f("protobuf_payload", 3, 1, 12, None, None),
      f("json_payload", 4, 1, 9, None, None),
      f("skipped", 5, 1, 9, None, None),
      f("serialize_error", 6, 1, 9, None, None),
      f("text_payload", 7, 1, 9, None, None),
    ],
    [],
    [],
    [],
    false,
  )
  {
    name: "conformance.proto",
    package_name: "conformance",
    syntax: "proto3",
    message_type: [request, response],
    enum_type: [
      {
        name: "WireFormat",
        value: [
          { name: "UNSPECIFIED", number: 0, },
          { name: "PROTOBUF", number: 1, },
          { name: "JSON", number: 2, },
          { name: "JSPB", number: 3, },
          { name: "TEXT_FORMAT", number: 4, },
        ],
      },
      {
        name: "TestCategory",
        value: [
          { name: "UNSPECIFIED_TEST", number: 0, },
          { name: "BINARY_TEST", number: 1, },
          { name: "JSON_TEST", number: 2, },
          { name: "JSON_IGNORE_UNKNOWN_PARSING_TEST", number: 3, },
          { name: "TEXT_FORMAT_TEST", number: 4, },
        ],
      },
    ],
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
  }
}

///|
/// A message that exercises every scalar kind, a packed repeat, a map, a
/// nested message, an enum and a oneof.
pub fn test_descriptor() -> @desc.FileDescriptorProto {
  let entry = m(
    "CountsEntry",
    [f("key", 1, 1, 9, None, None), f("value", 2, 1, 5, None, None)],
    [],
    [],
    [],
    true,
  )
  let nested = m("Nested", [f("value", 1, 1, 5, None, None)], [], [], [], false)
  let message = m(
    "TestAllTypes",
    [
      f("i32", 1, 1, 5, None, None),
      f("i64", 2, 1, 3, None, None),
      f("u32", 3, 1, 13, None, None),
      f("u64", 4, 1, 4, None, None),
      f("s32", 5, 1, 17, None, None),
      f("s64", 6, 1, 18, None, None),
      f("f32", 7, 1, 7, None, None),
      f("f64", 8, 1, 6, None, None),
      f("sf32", 9, 1, 15, None, None),
      f("sf64", 10, 1, 16, None, None),
      f("flt", 11, 1, 2, None, None),
      f("dbl", 12, 1, 1, None, None),
      f("flag", 13, 1, 8, None, None),
      f("text", 14, 1, 9, None, None),
      f("blob", 15, 1, 12, None, None),
      f("nums", 16, 3, 5, None, None),
      f("names", 17, 3, 9, None, None),
      f(
        "counts",
        18,
        3,
        11,
        Some(".conformance.TestAllTypes.CountsEntry"),
        None,
      ),
      f("child", 19, 1, 11, Some(".conformance.TestAllTypes.Nested"), None),
      f("color", 20, 1, 14, Some(".conformance.Color"), None),
      f("which_text", 21, 1, 9, None, Some(0)),
      f("which_i32", 22, 1, 5, None, Some(0)),
    ],
    [entry, nested],
    [],
    [{ name: "choice", }],
    false,
  )
  {
    name: "test_messages.proto",
    package_name: "conformance",
    syntax: "proto3",
    message_type: [message],
    enum_type: [
      {
        name: "Color",
        value: [{ name: "RED", number: 0, }, { name: "BLUE", number: 1, }],
      },
    ],
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
  }
}

///|
let conformance_types : @reflect.Types = build_types()

///|
fn build_types() -> @reflect.Types {
  let types = @reflect.Types::new()
  register(types, request_descriptor())
  return types
}

///|
fn register(types : @reflect.Types, file : @desc.FileDescriptorProto) -> Unit {
  let built = @desc.build_file(file) catch { _ => return }
  register_messages(types, built.messages)
}

///|
fn register_messages(
  types : @reflect.Types,
  messages : Array[@reflect.MessageDescriptor],
) -> Unit {
  for message in messages {
    let message_type = @dynamic.new_message_type(message)
    types.register_message(message_type) catch {
      _ => ()
    }
    register_messages(types, message.nested_messages)
  }
}

///|
/// Register the test message into the global registry, so a `Message` can be
/// built from its name.
pub fn register_test_types() -> Unit {
  let built = @desc.build_file(test_descriptor()) catch { _ => return }
  @reflect.global_files.register(built) catch {
    _ => ()
  }
  register_global(built.messages)
  for item in built.enums {
    @reflect.global_types.register_enum(@dynamic.new_enum_type(item)) catch {
      _ => ()
    }
  }
}

///|
fn register_global(messages : Array[@reflect.MessageDescriptor]) -> Unit {
  for message in messages {
    @reflect.global_types.register_message(@dynamic.new_message_type(message)) catch {
      _ => ()
    }
    register_global(message.nested_messages)
  }
}

///|
fn find_type(name : String) -> &@reflect.MessageType? {
  @reflect.global_types.find_message_by_name(name)
}

///|
fn get_string(message : &@reflect.Message, number : Int32) -> String {
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        message.get(field).string()
      } else {
        ""
      }
    None => ""
  }
}

///|
fn get_int(message : &@reflect.Message, number : Int32) -> Int32 {
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        match message.get(field) {
          @reflect.Enum(value) => value
          value => value.int().to_int()
        }
      } else {
        0
      }
    None => 0
  }
}

///|
fn get_bytes(message : &@reflect.Message, number : Int32) -> Bytes {
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        message.get(field).bytes()
      } else {
        b""
      }
    None => b""
  }
}

///|
fn has_field(message : &@reflect.Message, number : Int32) -> Bool {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.has(field)
    None => false
  }
}

///|
fn set_string(
  message : &@reflect.Message,
  number : Int32,
  text : String,
) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.set(field, @reflect.String(text))
    None => ()
  }
}

///|
fn set_bytes(
  message : &@reflect.Message,
  number : Int32,
  value : Bytes,
) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.set(field, @reflect.Bytes(value))
    None => ()
  }
}

///|
/// Answer one request: read the payload in the format it carries, write it in
/// the requested one.
pub fn handle(request_bytes : Bytes) -> Bytes {
  let request_type = match
    conformance_types.find_message_by_name("conformance.ConformanceRequest") {
    Some(found) => found
    None => return b""
  }
  let request = request_type.new_message()
  @proto.decode(request_bytes, request) catch {
    _ => return error_response("could not decode the request", false)
  }
  let message_type = get_string(request, 4)
  let output_format = get_int(request, 3)
  let message_type_info = match find_type(message_type) {
    Some(found) => found
    None => return error_response("unknown message type " + message_type, false)
  }
  let message = message_type_info.new_message()
  let decoded = if has_field(request, 1) {
    @proto.decode(get_bytes(request, 1), message) catch {
      err => {
        let _ = err
        return error_response("binary parse failed", true)
      }
    }
    true
  } else if has_field(request, 2) {
    @json.decode(get_string(request, 2), message) catch {
      _ => return error_response("json parse failed", true)
    }
    true
  } else if has_field(request, 8) {
    @text.decode(get_string(request, 8), message) catch {
      _ => return error_response("text parse failed", true)
    }
    true
  } else {
    false
  }
  if !decoded {
    return error_response("no payload", true)
  }
  let response = match
    conformance_types.find_message_by_name("conformance.ConformanceResponse") {
    Some(found) => found.new_message()
    None => return b""
  }
  let encoded = if output_format == 1 {
    let bytes = @proto.encode(message) catch {
      _ => return error_response("binary serialize failed", false)
    }
    set_bytes(response, 3, bytes)
    true
  } else if output_format == 2 {
    let text = @json.encode(message) catch {
      _ => return error_response("json serialize failed", false)
    }
    set_string(response, 4, text)
    true
  } else if output_format == 4 {
    let text = @text.encode(message) catch {
      _ => return error_response("text serialize failed", false)
    }
    set_string(response, 7, text)
    true
  } else {
    false
  }
  if !encoded {
    return error_response(
      "unsupported output format " + output_format.to_string(),
      false,
    )
  }
  @proto.encode(response) catch {
    _ => b""
  }
}

///|
fn error_response(text : String, parse : Bool) -> Bytes {
  let response = match
    conformance_types.find_message_by_name("conformance.ConformanceResponse") {
    Some(found) => found.new_message()
    None => return b""
  }
  if parse {
    set_string(response, 1, text)
  } else {
    set_string(response, 2, text)
  }
  @proto.encode(response) catch {
    _ => b""
  }
}
