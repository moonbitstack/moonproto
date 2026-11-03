// Well-known types as descriptors, plus registration into the global
// registries.

///|
fn field(
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
fn message(
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
fn wrapper(name : String, type_code : Int32) -> @desc.DescriptorProto {
  message(
    name,
    [field("value", 1, 1, type_code, None, None)],
    [],
    [],
    [],
    false,
  )
}

///|
fn struct_entry() -> @desc.DescriptorProto {
  message(
    "FieldsEntry",
    [
      field("key", 1, 1, 9, None, None),
      field("value", 2, 1, 11, Some(".google.protobuf.Value"), None),
    ],
    [],
    [],
    [],
    true,
  )
}

///|
fn value_message() -> @desc.DescriptorProto {
  message(
    "Value",
    [
      field("null_value", 1, 1, 14, Some(".google.protobuf.NullValue"), Some(0)),
      field("number_value", 2, 1, 1, None, Some(0)),
      field("string_value", 3, 1, 9, None, Some(0)),
      field("bool_value", 4, 1, 8, None, Some(0)),
      field("struct_value", 5, 1, 11, Some(".google.protobuf.Struct"), Some(0)),
      field("list_value", 6, 1, 11, Some(".google.protobuf.ListValue"), Some(0)),
    ],
    [],
    [],
    [{ name: "kind", }],
    false,
  )
}

///|
fn known_file_proto() -> @desc.FileDescriptorProto {
  let messages : Array[@desc.DescriptorProto] = [
    message(
      "Timestamp",
      [
        field("seconds", 1, 1, 3, None, None),
        field("nanos", 2, 1, 5, None, None),
      ],
      [],
      [],
      [],
      false,
    ),
    message(
      "Duration",
      [
        field("seconds", 1, 1, 3, None, None),
        field("nanos", 2, 1, 5, None, None),
      ],
      [],
      [],
      [],
      false,
    ),
    message(
      "Any",
      [
        field("type_url", 1, 1, 9, None, None),
        field("value", 2, 1, 12, None, None),
      ],
      [],
      [],
      [],
      false,
    ),
    message("Empty", [], [], [], [], false),
    message(
      "FieldMask",
      [field("paths", 1, 3, 9, None, None)],
      [],
      [],
      [],
      false,
    ),
    message(
      "Struct",
      [
        field(
          "fields",
          1,
          3,
          11,
          Some(".google.protobuf.Struct.FieldsEntry"),
          None,
        ),
      ],
      [struct_entry()],
      [],
      [],
      false,
    ),
    value_message(),
    message(
      "ListValue",
      [field("values", 1, 3, 11, Some(".google.protobuf.Value"), None)],
      [],
      [],
      [],
      false,
    ),
    wrapper("DoubleValue", 1),
    wrapper("FloatValue", 2),
    wrapper("Int64Value", 3),
    wrapper("UInt64Value", 4),
    wrapper("Int32Value", 5),
    wrapper("UInt32Value", 13),
    wrapper("BoolValue", 8),
    wrapper("StringValue", 9),
    wrapper("BytesValue", 12),
  ]
  {
    name: "google/protobuf/well_known.proto",
    package_name: "google.protobuf",
    syntax: "proto3",
    message_type: messages,
    enum_type: [
      { name: "NullValue", value: [{ name: "NULL_VALUE", number: 0, }], },
    ],
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
  }
}

///|
/// The file descriptor holding every well-known type.
pub fn file_descriptor() -> @reflect.FileDescriptor raise @desc.Refused {
  @desc.build_file(known_file_proto())
}

///|
/// The descriptor for `name` (for example `google.protobuf.Timestamp`).
pub fn message_descriptor(
  name : String,
) -> @reflect.MessageDescriptor? raise @desc.Refused {
  let file = file_descriptor()
  for message in file.messages {
    if message.full_name == name {
      return Some(message)
    }
  }
  None
}

///|
/// Register every well-known type, so JSON `Any` and dynamic construction can
/// find them by name.
pub fn register_all() -> Unit {
  let file = file_descriptor() catch { _ => return }
  @reflect.global_files.register(file) catch {
    _ => ()
  }
  register_messages(file.messages)
  for item in file.enums {
    @reflect.global_types.register_enum(@dynamic.new_enum_type(item)) catch {
      _ => ()
    }
  }
}

///|
fn register_messages(messages : Array[@reflect.MessageDescriptor]) -> Unit {
  for message in messages {
    @reflect.global_types.register_message(@dynamic.new_message_type(message)) catch {
      _ => ()
    }
    register_messages(message.nested_messages)
  }
}
