// The plugin protocol's descriptors and the mapping to and from `desc` records.

///|
pub(all) suberror Refused {
  Protocol(String)
  Proto(@proto.Refused)
  Desc(@desc.Refused)
  /// A field refers to a type no file in the request declares, so the
  /// generated source could not name it.
  Unknown(String)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Protocol(message) => logger.write_string("protocol: " + message)
    Proto(_) => logger.write_string("message could not be decoded")
    Desc(_) => logger.write_string("descriptor could not be built")
    Unknown(name) => logger.write_string("no generated type for " + name)
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// One request to generate code.
pub(all) struct Request {
  files_to_generate : Array[String]
  parameter : String
  proto_file : Array[@desc.FileDescriptorProto]
}

///|
fn f(
  name : String,
  number : Int32,
  label : Int32,
  type_code : Int32,
  type_name : String?,
) -> @desc.FieldDescriptorProto {
  {
    name,
    number,
    label,
    type_code,
    type_name,
    json_name: None,
    default_value: None,
    oneof_index: None,
    proto3_optional: false,
    packed_off: false,
    extendee: None,
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn m(
  name : String,
  fields : Array[@desc.FieldDescriptorProto],
  nested : Array[@desc.DescriptorProto],
) -> @desc.DescriptorProto {
  {
    name,
    field: fields,
    nested_type: nested,
    enum_type: [],
    extension: [],
    oneof_decl: [],
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry: false,
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn descriptor_file() -> @desc.FileDescriptorProto {
  let options = m("MessageOptions", [f("map_entry", 7, 1, 8, None)], [])
  let field_options = m("FieldOptions", [f("packed", 2, 1, 8, None)], [])
  let extension_range = m(
    "ExtensionRange",
    [f("start", 1, 1, 5, None), f("end", 2, 1, 5, None)],
    [],
  )
  let reserved_range = m(
    "ReservedRange",
    [f("start", 1, 1, 5, None), f("end", 2, 1, 5, None)],
    [],
  )
  let enum_value = m(
    "EnumValueDescriptorProto",
    [f("name", 1, 1, 9, None), f("number", 2, 1, 5, None)],
    [],
  )
  let enum_descriptor = m(
    "EnumDescriptorProto",
    [
      f("name", 1, 1, 9, None),
      f("value", 2, 3, 11, Some(".google.protobuf.EnumValueDescriptorProto")),
    ],
    [enum_value],
  )
  let oneof_descriptor = m("OneofDescriptorProto", [f("name", 1, 1, 9, None)], [])
  let field_descriptor = m(
    "FieldDescriptorProto",
    [
      f("name", 1, 1, 9, None),
      f("number", 3, 1, 5, None),
      f("label", 4, 1, 14, Some(".google.protobuf.FieldDescriptorProto.Label")),
      f("type", 5, 1, 14, Some(".google.protobuf.FieldDescriptorProto.Type")),
      f("type_name", 6, 1, 9, None),
      f("default_value", 7, 1, 9, None),
      f("options", 8, 1, 11, Some(".google.protobuf.FieldOptions")),
      f("oneof_index", 9, 1, 5, None),
      f("json_name", 10, 1, 9, None),
      f("proto3_optional", 17, 1, 8, None),
    ],
    [],
  )
  let message_descriptor = m(
    "DescriptorProto",
    [
      f("name", 1, 1, 9, None),
      f("field", 2, 3, 11, Some(".google.protobuf.FieldDescriptorProto")),
      f("nested_type", 3, 3, 11, Some(".google.protobuf.DescriptorProto")),
      f("enum_type", 4, 3, 11, Some(".google.protobuf.EnumDescriptorProto")),
      f(
        "extension_range",
        5,
        3,
        11,
        Some(".google.protobuf.DescriptorProto.ExtensionRange"),
      ),
      f("extension", 6, 3, 11, Some(".google.protobuf.FieldDescriptorProto")),
      f("options", 7, 1, 11, Some(".google.protobuf.MessageOptions")),
      f("oneof_decl", 8, 3, 11, Some(".google.protobuf.OneofDescriptorProto")),
      f(
        "reserved_range",
        9,
        3,
        11,
        Some(".google.protobuf.DescriptorProto.ReservedRange"),
      ),
      f("reserved_name", 10, 3, 9, None),
    ],
    [extension_range, reserved_range],
  )
  let method_descriptor = m(
    "MethodDescriptorProto",
    [
      f("name", 1, 1, 9, None),
      f("input_type", 2, 1, 9, None),
      f("output_type", 3, 1, 9, None),
      f("client_streaming", 5, 1, 8, None),
      f("server_streaming", 6, 1, 8, None),
    ],
    [],
  )
  let service_descriptor = m(
    "ServiceDescriptorProto",
    [
      f("name", 1, 1, 9, None),
      f("method", 2, 3, 11, Some(".google.protobuf.MethodDescriptorProto")),
    ],
    [],
  )
  let file_descriptor = m(
    "FileDescriptorProto",
    [
      f("name", 1, 1, 9, None),
      f("package", 2, 1, 9, None),
      f("dependency", 3, 3, 9, None),
      f("message_type", 4, 3, 11, Some(".google.protobuf.DescriptorProto")),
      f("enum_type", 5, 3, 11, Some(".google.protobuf.EnumDescriptorProto")),
      f("service", 6, 3, 11, Some(".google.protobuf.ServiceDescriptorProto")),
      f("extension", 7, 3, 11, Some(".google.protobuf.FieldDescriptorProto")),
      f("syntax", 12, 1, 9, None),
    ],
    [],
  )
  let enums : Array[@desc.EnumDescriptorProto] = [
    {
      name: "Type",
      value: [
        { name: "TYPE_DOUBLE", number: 1, },
        { name: "TYPE_FLOAT", number: 2, },
        { name: "TYPE_INT64", number: 3, },
        { name: "TYPE_UINT64", number: 4, },
        { name: "TYPE_INT32", number: 5, },
        { name: "TYPE_FIXED64", number: 6, },
        { name: "TYPE_FIXED32", number: 7, },
        { name: "TYPE_BOOL", number: 8, },
        { name: "TYPE_STRING", number: 9, },
        { name: "TYPE_GROUP", number: 10, },
        { name: "TYPE_MESSAGE", number: 11, },
        { name: "TYPE_BYTES", number: 12, },
        { name: "TYPE_UINT32", number: 13, },
        { name: "TYPE_ENUM", number: 14, },
        { name: "TYPE_SFIXED32", number: 15, },
        { name: "TYPE_SFIXED64", number: 16, },
        { name: "TYPE_SINT32", number: 17, },
        { name: "TYPE_SINT64", number: 18, },
      ],
      features: @desc.features_auto,
      options: [],
    },
    {
      name: "Label",
      value: [
        { name: "LABEL_OPTIONAL", number: 1, },
        { name: "LABEL_REQUIRED", number: 2, },
        { name: "LABEL_REPEATED", number: 3, },
      ],
      features: @desc.features_auto,
      options: [],
    },
  ]
  {
    name: "google/protobuf/descriptor.proto",
    package_name: "google.protobuf",
    syntax: "proto3",
    message_type: [
      file_descriptor, message_descriptor, field_descriptor, oneof_descriptor, enum_descriptor,
      enum_value, service_descriptor, method_descriptor, extension_range, reserved_range,
      options, field_options,
    ],
    enum_type: enums,
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
    edition: None,
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn plugin_file() -> @desc.FileDescriptorProto {
  let response_file = m(
    "File",
    [
      f("name", 1, 1, 9, None),
      f("insertion_point", 2, 1, 9, None),
      f("content", 15, 1, 9, None),
    ],
    [],
  )
  let request = m(
    "CodeGeneratorRequest",
    [
      f("file_to_generate", 1, 3, 9, None),
      f("parameter", 2, 1, 9, None),
      f("proto_file", 15, 3, 11, Some(".google.protobuf.FileDescriptorProto")),
    ],
    [],
  )
  let response = m(
    "CodeGeneratorResponse",
    [
      f("error", 1, 1, 9, None),
      f("supported_features", 2, 1, 4, None),
      f(
        "file",
        15,
        3,
        11,
        Some(".google.protobuf.compiler.CodeGeneratorResponse.File"),
      ),
    ],
    [response_file],
  )
  {
    name: "google/protobuf/plugin.proto",
    package_name: "google.protobuf.compiler",
    syntax: "proto3",
    message_type: [request, response],
    enum_type: [],
    service: [],
    extension: [],
    dependency: ["google/protobuf/descriptor.proto"],
    public_dependency: [],
    edition: None,
    features: @desc.features_auto,
    options: [],
  }
}

///|
/// The two files the protocol needs, built once.
pub fn types() -> @reflect.Types {
  let types = @reflect.Types::new()
  let files : Array[@desc.FileDescriptorProto] = [
    descriptor_file(),
    plugin_file(),
  ]
  for file in files {
    let built = @desc.build_file(file) catch { _ => continue }
    register_messages(types, built.messages)
  }
  types
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
    // Nested messages are built through the global registry, so the protocol
    // types have to be visible there too.
    @reflect.global_types.register_message(message_type) catch {
      _ => ()
    }
    register_messages(types, message.nested_messages)
  }
}

///|
pub let plugin_types : @reflect.Types = types()

///|
fn find_type(
  types : @reflect.Types,
  name : String,
) -> &@reflect.MessageType raise Refused {
  match types.find_message_by_name(name) {
    Some(found) => found
    None => raise Protocol("no type " + name)
  }
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
fn get_bool(message : &@reflect.Message, number : Int32) -> Bool {
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        message.get(field).bool()
      } else {
        false
      }
    None => false
  }
}

///|
fn get_strings(message : &@reflect.Message, number : Int32) -> Array[String] {
  let out : Array[String] = []
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        match message.get(field) {
          @reflect.ListView(list) =>
            for i in 0..<list.length() {
              out.push(list.get(i).string())
            }
          _ => ()
        }
      }
    None => ()
  }
  out
}

///|
/// A singular message field, absent when unset.
fn get_message(
  message : &@reflect.Message,
  number : Int32,
) -> &@reflect.Message? {
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        Some(message.get(field).message())
      } else {
        None
      }
    None => None
  }
}

///|
fn get_messages(
  message : &@reflect.Message,
  number : Int32,
) -> Array[&@reflect.Message] {
  let out : Array[&@reflect.Message] = []
  match message.descriptor().field_by_number(number) {
    Some(field) =>
      if message.has(field) {
        match message.get(field) {
          @reflect.ListView(list) =>
            for i in 0..<list.length() {
              out.push(list.get(i).message())
            }
          _ => ()
        }
      }
    None => ()
  }
  out
}

///|
/// Decode a `CodeGeneratorRequest`.
pub fn decode_request(bytes : Bytes) -> Request raise Refused {
  let message_type = find_type(
    plugin_types, "google.protobuf.compiler.CodeGeneratorRequest",
  )
  let message = message_type.new_message()
  @proto.decode(bytes, message) catch {
    err => raise Proto(err)
  }
  let files : Array[@desc.FileDescriptorProto] = []
  for item in get_messages(message, 15) {
    files.push(to_file_proto(item))
  }
  {
    files_to_generate: get_strings(message, 1),
    parameter: get_string(message, 2),
    proto_file: files,
  }
}

///|
fn to_file_proto(message : &@reflect.Message) -> @desc.FileDescriptorProto {
  let messages : Array[@desc.DescriptorProto] = []
  for item in get_messages(message, 4) {
    messages.push(to_message_proto(item))
  }
  let enums : Array[@desc.EnumDescriptorProto] = []
  for item in get_messages(message, 5) {
    enums.push(to_enum_proto(item))
  }
  let services : Array[@desc.ServiceDescriptorProto] = []
  for item in get_messages(message, 6) {
    services.push(to_service_proto(item))
  }
  let extensions : Array[@desc.FieldDescriptorProto] = []
  for item in get_messages(message, 7) {
    extensions.push(to_field_proto(item))
  }
  {
    name: get_string(message, 1),
    package_name: get_string(message, 2),
    syntax: get_string(message, 12),
    message_type: messages,
    enum_type: enums,
    service: services,
    extension: extensions,
    dependency: get_strings(message, 3),
    public_dependency: [],
    edition: None,
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn to_message_proto(message : &@reflect.Message) -> @desc.DescriptorProto {
  let fields : Array[@desc.FieldDescriptorProto] = []
  for item in get_messages(message, 2) {
    fields.push(to_field_proto(item))
  }
  let nested : Array[@desc.DescriptorProto] = []
  for item in get_messages(message, 3) {
    nested.push(to_message_proto(item))
  }
  let enums : Array[@desc.EnumDescriptorProto] = []
  for item in get_messages(message, 4) {
    enums.push(to_enum_proto(item))
  }
  let extension_ranges : Array[(Int32, Int32)] = []
  for item in get_messages(message, 5) {
    extension_ranges.push((get_int(item, 1), get_int(item, 2)))
  }
  let extensions : Array[@desc.FieldDescriptorProto] = []
  for item in get_messages(message, 6) {
    extensions.push(to_field_proto(item))
  }
  let oneofs : Array[@desc.OneofDescriptorProto] = []
  for item in get_messages(message, 8) {
    oneofs.push({ name: get_string(item, 1), })
  }
  let reserved_ranges : Array[(Int32, Int32)] = []
  for item in get_messages(message, 9) {
    reserved_ranges.push((get_int(item, 1), get_int(item, 2)))
  }
  let map_entry = match get_message(message, 7) {
    Some(options) => get_bool(options, 7)
    None => false
  }
  {
    name: get_string(message, 1),
    field: fields,
    nested_type: nested,
    enum_type: enums,
    extension: extensions,
    oneof_decl: oneofs,
    reserved_range: reserved_ranges,
    reserved_name: get_strings(message, 10),
    extension_range: extension_ranges,
    map_entry,
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn to_field_proto(message : &@reflect.Message) -> @desc.FieldDescriptorProto {
  let packed_off = match get_message(message, 8) {
    Some(options) => if get_bool(options, 2) { false } else { true }
    None => false
  }
  {
    name: get_string(message, 1),
    number: get_int(message, 3),
    label: get_int(message, 4),
    type_code: get_int(message, 5),
    type_name: match get_string(message, 6) {
      "" => None
      text => Some(text)
    },
    json_name: match get_string(message, 10) {
      "" => None
      text => Some(text)
    },
    default_value: match get_string(message, 7) {
      "" => None
      text => Some(text)
    },
    oneof_index: match message.descriptor().field_by_number(9) {
      Some(field) =>
        if message.has(field) {
          Some(get_int(message, 9))
        } else {
          None
        }
      None => None
    },
    proto3_optional: get_bool(message, 17),
    packed_off,
    extendee: match get_string(message, 2) {
      "" => None
      text => Some(text)
    },
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn to_enum_proto(message : &@reflect.Message) -> @desc.EnumDescriptorProto {
  let values : Array[@desc.EnumValueDescriptorProto] = []
  for item in get_messages(message, 2) {
    values.push({ name: get_string(item, 1), number: get_int(item, 2), })
  }
  {
    name: get_string(message, 1),
    value: values,
    features: @desc.features_auto,
    options: [],
  }
}

///|
fn to_service_proto(
  message : &@reflect.Message,
) -> @desc.ServiceDescriptorProto {
  let methods : Array[@desc.MethodDescriptorProto] = []
  for item in get_messages(message, 2) {
    methods.push({
      name: get_string(item, 1),
      input_type: get_string(item, 2),
      output_type: get_string(item, 3),
      client_streaming: get_bool(item, 5),
      server_streaming: get_bool(item, 6),
    })
  }
  { name: get_string(message, 1), methods, }
}

///|
/// Encode a `CodeGeneratorResponse`.
pub fn encode_response(
  files : Array[(String, String)],
  error : String?,
) -> Bytes raise Refused {
  let message_type = find_type(
    plugin_types, "google.protobuf.compiler.CodeGeneratorResponse",
  )
  let message = message_type.new_message()
  let file_type = find_type(
    plugin_types, "google.protobuf.compiler.CodeGeneratorResponse.File",
  )
  match error {
    Some(text) =>
      match message.descriptor().field_by_number(1) {
        Some(field) => message.set(field, @reflect.String(text))
        None => ()
      }
    None => ()
  }
  let file_field = match message.descriptor().field_by_number(15) {
    Some(field) => field
    None => raise Protocol("no file field")
  }
  let list = message.mutable(file_field).list()
  for pair in files {
    let entry = file_type.new_message()
    match entry.descriptor().field_by_number(1) {
      Some(field) => entry.set(field, @reflect.String(pair.0))
      None => ()
    }
    match entry.descriptor().field_by_number(15) {
      Some(field) => entry.set(field, @reflect.String(pair.1))
      None => ()
    }
    list.append(@reflect.Message(entry))
  }
  @proto.encode(message) catch {
    err => raise Proto(err)
  }
}

// -- the inverse direction, used by tests and by a request-file mode ----------

///|
fn new_message(name : String) -> &@reflect.Message raise Refused {
  find_type(plugin_types, name).new_message()
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
fn set_int(message : &@reflect.Message, number : Int32, value : Int32) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.set(field, @reflect.Int32(value))
    None => ()
  }
}

///|
fn set_enum(message : &@reflect.Message, number : Int32, value : Int32) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.set(field, @reflect.Enum(value))
    None => ()
  }
}

///|
fn set_bool(message : &@reflect.Message, number : Int32, value : Bool) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.set(field, @reflect.Bool(value))
    None => ()
  }
}

///|
fn add_message(
  message : &@reflect.Message,
  number : Int32,
  child : &@reflect.Message,
) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.mutable(field).list().append(@reflect.Message(child))
    None => ()
  }
}

///|
fn add_string(
  message : &@reflect.Message,
  number : Int32,
  text : String,
) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.mutable(field).list().append(@reflect.String(text))
    None => ()
  }
}

///|
fn encode_field(
  field : @desc.FieldDescriptorProto,
) -> &@reflect.Message raise Refused {
  let message = new_message("google.protobuf.FieldDescriptorProto")
  set_string(message, 1, field.name)
  set_int(message, 3, field.number)
  match field.extendee {
    Some(name) => set_string(message, 2, name)
    None => ()
  }
  set_enum(message, 4, field.label)
  set_enum(message, 5, field.type_code)
  match field.type_name {
    Some(name) => set_string(message, 6, name)
    None => ()
  }
  match field.json_name {
    Some(name) => set_string(message, 10, name)
    None => ()
  }
  match field.default_value {
    Some(value) => set_string(message, 7, value)
    None => ()
  }
  match field.oneof_index {
    Some(index) => set_int(message, 9, index)
    None => ()
  }
  if field.proto3_optional {
    set_bool(message, 17, true)
  }
  message
}

///|
fn encode_enum(
  item : @desc.EnumDescriptorProto,
) -> &@reflect.Message raise Refused {
  let message = new_message("google.protobuf.EnumDescriptorProto")
  set_string(message, 1, item.name)
  for value in item.value {
    let value_message = new_message("google.protobuf.EnumValueDescriptorProto")
    set_string(value_message, 1, value.name)
    set_int(value_message, 2, value.number)
    add_message(message, 2, value_message)
  }
  message
}

///|
fn encode_message(
  item : @desc.DescriptorProto,
) -> &@reflect.Message raise Refused {
  let message = new_message("google.protobuf.DescriptorProto")
  set_string(message, 1, item.name)
  for field in item.field {
    add_message(message, 2, encode_field(field))
  }
  for nested in item.nested_type {
    add_message(message, 3, encode_message(nested))
  }
  for enum_item in item.enum_type {
    add_message(message, 4, encode_enum(enum_item))
  }
  for field in item.extension {
    add_message(message, 6, encode_field(field))
  }
  for oneof in item.oneof_decl {
    let oneof_message = new_message("google.protobuf.OneofDescriptorProto")
    set_string(oneof_message, 1, oneof.name)
    add_message(message, 8, oneof_message)
  }
  for name in item.reserved_name {
    add_string(message, 10, name)
  }
  message
}

///|
fn encode_service(
  item : @desc.ServiceDescriptorProto,
) -> &@reflect.Message raise Refused {
  let message = new_message("google.protobuf.ServiceDescriptorProto")
  set_string(message, 1, item.name)
  for m in item.methods {
    let method_message = new_message("google.protobuf.MethodDescriptorProto")
    set_string(method_message, 1, m.name)
    set_string(method_message, 2, m.input_type)
    set_string(method_message, 3, m.output_type)
    if m.client_streaming {
      set_bool(method_message, 5, true)
    }
    if m.server_streaming {
      set_bool(method_message, 6, true)
    }
    add_message(message, 2, method_message)
  }
  message
}

///|
fn encode_file(
  file : @desc.FileDescriptorProto,
) -> &@reflect.Message raise Refused {
  let message = new_message("google.protobuf.FileDescriptorProto")
  set_string(message, 1, file.name)
  set_string(message, 2, file.package_name)
  set_string(message, 12, file.syntax)
  for dependency in file.dependency {
    add_string(message, 3, dependency)
  }
  for item in file.message_type {
    add_message(message, 4, encode_message(item))
  }
  for item in file.enum_type {
    add_message(message, 5, encode_enum(item))
  }
  for item in file.service {
    add_message(message, 6, encode_service(item))
  }
  for item in file.extension {
    add_message(message, 7, encode_field(item))
  }
  message
}

///|
/// Encode a request, the inverse of `decode_request`.
pub fn encode_request(request : Request) -> Bytes raise Refused {
  let message = new_message("google.protobuf.compiler.CodeGeneratorRequest")
  for name in request.files_to_generate {
    add_string(message, 1, name)
  }
  if request.parameter.length() > 0 {
    set_string(message, 2, request.parameter)
  }
  for file in request.proto_file {
    add_message(message, 15, encode_file(file))
  }
  @proto.encode(message) catch {
    err => raise Proto(err)
  }
}

///|
/// Decode a response: the generated files and the error, if any.
pub fn decode_response(
  bytes : Bytes,
) -> (Array[(String, String)], String?) raise Refused {
  let message = new_message("google.protobuf.compiler.CodeGeneratorResponse")
  @proto.decode(bytes, message) catch {
    err => raise Proto(err)
  }
  let files : Array[(String, String)] = []
  for item in get_messages(message, 15) {
    files.push((get_string(item, 1), get_string(item, 15)))
  }
  let error = match get_string(message, 1) {
    "" => None
    text => Some(text)
  }
  (files, error)
}
