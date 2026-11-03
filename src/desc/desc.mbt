// Descriptor construction from the proto form.

///|
pub(all) struct FieldDescriptorProto {
  name : String
  number : Int32
  /// 1 optional, 2 required, 3 repeated.
  label : Int32
  /// 1..18, the `descriptor.proto` type numbers.
  type_code : Int32
  /// The referenced message or enum, dotted and possibly leading-dot.
  type_name : String?
  json_name : String?
  default_value : String?
  oneof_index : Int32?
  proto3_optional : Bool
  /// `[packed = false]` on a repeated numeric field.
  packed_off : Bool
}

///|
pub(all) struct OneofDescriptorProto {
  name : String
}

///|
pub(all) struct EnumValueDescriptorProto {
  name : String
  number : Int32
}

///|
pub(all) struct EnumDescriptorProto {
  name : String
  value : Array[EnumValueDescriptorProto]
}

///|
pub(all) struct DescriptorProto {
  name : String
  field : Array[FieldDescriptorProto]
  nested_type : Array[DescriptorProto]
  enum_type : Array[EnumDescriptorProto]
  extension : Array[FieldDescriptorProto]
  oneof_decl : Array[OneofDescriptorProto]
  reserved_range : Array[(Int32, Int32)]
  reserved_name : Array[String]
  extension_range : Array[(Int32, Int32)]
  /// `options.map_entry`: this nested message is a map field's entry.
  map_entry : Bool
}

///|
pub(all) struct MethodDescriptorProto {
  name : String
  input_type : String
  output_type : String
  client_streaming : Bool
  server_streaming : Bool
}

///|
pub(all) struct ServiceDescriptorProto {
  name : String
  methods : Array[MethodDescriptorProto]
}

///|
pub(all) struct FileDescriptorProto {
  name : String
  package_name : String
  /// "proto2", "proto3" or "editions".
  syntax : String
  message_type : Array[DescriptorProto]
  enum_type : Array[EnumDescriptorProto]
  service : Array[ServiceDescriptorProto]
  extension : Array[FieldDescriptorProto]
  dependency : Array[String]
  public_dependency : Array[Int32]
}

///|
/// A build refusal.
pub(all) suberror Refused {
  Name(String)
  Number(Int32)
  Type(String)
  Syntax(String)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Name(name) => logger.write_string("bad name " + name)
    Number(number) => logger.write_string("bad number " + number.to_string())
    Type(name) => logger.write_string("unresolved type " + name)
    Syntax(text) => logger.write_string("bad syntax " + text)
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// Build a runtime file descriptor from the proto form.
pub fn build_file(
  proto : FileDescriptorProto,
) -> @reflect.FileDescriptor raise Refused {
  let syntax = parse_syntax(proto.syntax)
  let messages : Array[@reflect.MessageDescriptor] = []
  for message in proto.message_type {
    messages.push(
      build_message(message, proto.package_name, proto.name, syntax),
    )
  }
  let enums : Array[@reflect.EnumDescriptor] = []
  for item in proto.enum_type {
    enums.push(build_enum(item, proto.package_name, proto.name))
  }
  let services : Array[@reflect.ServiceDescriptor] = []
  for service in proto.service {
    services.push(build_service(service, proto.package_name, proto.name))
  }
  let extensions : Array[@reflect.FieldDescriptor] = []
  for field in proto.extension {
    extensions.push(
      build_field(
        field,
        proto.package_name,
        proto.package_name,
        proto.name,
        syntax,
        None,
      ),
    )
  }
  {
    path: proto.name,
    package_name: proto.package_name,
    syntax,
    messages,
    enums,
    services,
    extensions,
    dependencies: proto.dependency,
    public_dependencies: [],
  }
}

///|
fn parse_syntax(text : String) -> @reflect.Syntax {
  match text {
    "proto2" => @reflect.Proto2
    "editions" => @reflect.Editions
    _ => @reflect.Proto3
  }
}

///|
fn build_message(
  proto : DescriptorProto,
  package_name : String,
  file_path : String,
  syntax : @reflect.Syntax,
) -> @reflect.MessageDescriptor raise Refused {
  let full_name = @reflect.qualify(package_name, proto.name)
  let nested : Array[@reflect.MessageDescriptor] = []
  for item in proto.nested_type {
    nested.push(
      build_message(item, package_name + "." + proto.name, file_path, syntax),
    )
  }
  let enums : Array[@reflect.EnumDescriptor] = []
  for item in proto.enum_type {
    enums.push(build_enum(item, package_name + "." + proto.name, file_path))
  }
  let oneofs : Array[@reflect.OneofDescriptor] = []
  for oneof in proto.oneof_decl {
    oneofs.push({ name: oneof.name, synthetic: false, field_numbers: [], })
  }
  let fields : Array[@reflect.FieldDescriptor] = []
  for field in proto.field {
    let built = build_field(
      field,
      full_name,
      package_name + "." + proto.name,
      file_path,
      syntax,
      Some(nested),
    )
    fields.push(built)
  }
  // Mark synthetic oneofs: a oneof whose only field carries proto3_optional.
  for i in 0..<oneofs.length() {
    let mut count = 0
    let mut synthetic = true
    for field in fields {
      match field.oneof_index {
        Some(field_oneof) =>
          if field_oneof == i {
            count = count + 1
            if !proto3_optional_of(proto, field.number) {
              synthetic = false
            }
          }
        None => ()
      }
    }
    oneofs[i] = {
      name: oneofs[i].name,
      synthetic: synthetic && count == 1,
      field_numbers: oneofs[i].field_numbers,
    }
  }
  // Fill oneof membership.
  for field in fields {
    match field.oneof_index {
      Some(field_oneof) =>
        if field_oneof >= 0 && field_oneof < oneofs.length() {
          let current = oneofs[field_oneof]
          let numbers = current.field_numbers.copy()
          numbers.push(field.number)
          oneofs[field_oneof] = {
            name: current.name,
            synthetic: current.synthetic,
            field_numbers: numbers,
          }
        }
      None => ()
    }
  }
  let required : Array[Int32] = []
  for field in fields {
    if field.cardinality == @reflect.Required {
      required.push(field.number)
    }
  }
  let map_entry_field = match proto.map_entry {
    true => {
      let key = find_field(fields, 1)
      let value = find_field(fields, 2)
      (key, value)
    }
    false => (None, None)
  }
  {
    name: proto.name,
    full_name,
    syntax,
    fields,
    oneofs,
    is_map_entry: proto.map_entry,
    reserved_names: proto.reserved_name,
    reserved_ranges: proto.reserved_range,
    required_numbers: required,
    extension_ranges: proto.extension_range,
    nested_messages: nested,
    nested_enums: enums,
    nested_extensions: [],
    file_path,
    map_key: map_entry_field.0,
    map_value: map_entry_field.1,
  }
}

///|
fn proto3_optional_of(proto : DescriptorProto, number : Int32) -> Bool {
  for field in proto.field {
    if field.number == number {
      return field.proto3_optional
    }
  }
  false
}

///|
fn find_field(
  fields : Array[@reflect.FieldDescriptor],
  number : Int32,
) -> @reflect.FieldDescriptor? {
  for field in fields {
    if field.number == number {
      return Some(field)
    }
  }
  None
}

///|
fn build_field(
  proto : FieldDescriptorProto,
  containing : String,
  scope : String,
  file_path : String,
  syntax : @reflect.Syntax,
  siblings : Array[@reflect.MessageDescriptor]?,
) -> @reflect.FieldDescriptor raise Refused {
  let _ = file_path
  let kind = match @reflect.Kind::of(proto.type_code) {
    Some(kind) => kind
    None => raise Type(proto.name)
  }
  let cardinality = match proto.label {
    2 => @reflect.Required
    3 => @reflect.Repeated
    _ => @reflect.Optional
  }
  let resolved = match proto.type_name {
    Some(name) => resolve_type(name, scope)
    None => None
  }
  let mut is_map = false
  let mut map_key_field = None
  let mut map_value_field = None
  if cardinality == @reflect.Repeated && kind == @reflect.Message {
    match resolved {
      Some(entry_name) =>
        match find_nested(siblings, entry_name) {
          Some(entry) =>
            if entry.is_map_entry {
              is_map = true
              map_key_field = entry.map_key
              map_value_field = entry.map_value
            }
          None => ()
        }
      None => ()
    }
  }
  let json_name = match proto.json_name {
    Some(name) =>
      if name.length() > 0 {
        name
      } else {
        to_json_name(proto.name)
      }
    None => to_json_name(proto.name)
  }
  let text_name = if kind == @reflect.Group {
    @reflect.short_name(
      match resolved {
        Some(name) => name
        None => proto.name
      },
    )
  } else {
    proto.name
  }
  let packed = if cardinality == @reflect.Repeated && kind.is_numeric() {
    match syntax {
      @reflect.Proto3 | @reflect.Editions => !proto.packed_off
      @reflect.Proto2 => false
    }
  } else {
    false
  }
  let mut has_default = false
  if syntax == @reflect.Proto2 {
    match proto.default_value {
      Some(_) => has_default = true
      None => ()
    }
  }
  let default_value = if has_default {
    parse_default(kind, proto.default_value, resolved)
  } else {
    @reflect.zero_value(kind)
  }
  let has_presence = syntax == @reflect.Proto2 ||
    cardinality == @reflect.Required ||
    proto.oneof_index is Some(_) ||
    proto.proto3_optional ||
    kind.is_message()
  {
    name: proto.name,
    full_name: containing + "." + proto.name,
    number: proto.number,
    kind,
    cardinality,
    json_name,
    text_name,
    has_presence,
    is_extension: false,
    is_map,
    packed,
    oneof_index: proto.oneof_index,
    message_type: if kind.is_message() {
      resolved
    } else {
      None
    },
    enum_type: if kind == @reflect.Enum {
      resolved
    } else {
      None
    },
    has_default,
    default_value,
    default_enum_name: proto.default_value,
    containing_message: containing,
    map_key_field,
    map_value_field,
  }
}

///|
fn resolve_type(name : String, scope : String) -> String? {
  if name.length() == 0 {
    return None
  }
  if char_at(name, 0) == '.' {
    return Some(name[1:].to_owned())
  }
  if name.contains(".") {
    return Some(name)
  }
  Some(scope + "." + name)
}

///|
fn find_nested(
  siblings : Array[@reflect.MessageDescriptor]?,
  name : String,
) -> @reflect.MessageDescriptor? {
  match siblings {
    Some(items) => {
      for item in items {
        if item.full_name == name || item.name == name {
          return Some(item)
        }
      }
      None
    }
    None => None
  }
}

///|
fn parse_default(
  kind : @reflect.Kind,
  text : String?,
  resolved : String?,
) -> @reflect.Value {
  let _ = resolved
  match text {
    Some(value) =>
      match kind {
        @reflect.Bool => @reflect.Bool(value == "true")
        @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 =>
          @reflect.Int32(parse_int_text(value).to_int())
        @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>
          @reflect.Int64(parse_int_text(value))
        @reflect.Uint32 | @reflect.Fixed32 =>
          @reflect.Uint32(parse_int_text(value).to_int().reinterpret_as_uint())
        @reflect.Uint64 | @reflect.Fixed64 =>
          @reflect.Uint64(parse_int_text(value).reinterpret_as_uint64())
        @reflect.Float =>
          @reflect.Float(@float.Float::from_double(parse_double_text(value)))
        @reflect.Double => @reflect.Double(parse_double_text(value))
        @reflect.String => @reflect.String(value)
        @reflect.Bytes => @reflect.Bytes(@utf8.encode(value))
        _ => @reflect.Invalid
      }
    None => @reflect.zero_value(kind)
  }
}

///|
fn build_enum(
  proto : EnumDescriptorProto,
  scope : String,
  file_path : String,
) -> @reflect.EnumDescriptor {
  let full_name = @reflect.qualify(scope, proto.name)
  let values : Array[@reflect.EnumValueDescriptor] = []
  for value in proto.value {
    values.push({
      name: value.name,
      number: value.number,
      full_name: @reflect.qualify(scope, value.name),
    })
  }
  { name: proto.name, full_name, values, closed: false, file_path, }
}

///|
fn build_service(
  proto : ServiceDescriptorProto,
  scope : String,
  file_path : String,
) -> @reflect.ServiceDescriptor {
  let full_name = @reflect.qualify(scope, proto.name)
  let methods : Array[@reflect.MethodDescriptor] = []
  for m in proto.methods {
    methods.push({
      name: m.name,
      full_name: full_name + "." + m.name,
      input_type: m.input_type,
      output_type: m.output_type,
      streaming_client: m.client_streaming,
      streaming_server: m.server_streaming,
    })
  }
  { name: proto.name, full_name, methods, file_path, }
}

///|
/// `foo_bar` becomes `fooBar`, the JSON name default.
pub fn to_json_name(name : String) -> String {
  let out = Buffer()
  let mut upper = false
  for i in 0..<name.length() {
    let ch = char_at(name, i)
    if ch == '_' {
      upper = true
    } else if upper {
      out.write_string_utf8(upper_char(ch).to_string())
      upper = false
    } else {
      out.write_string_utf8(ch.to_string())
    }
  }
  @utf8.decode(out.to_bytes()) catch {
    _ => name
  }
}

///|
fn char_at(text : String, index : Int32) -> Char {
  text[index].to_int().to_char().unwrap_or('?')
}

///|
fn parse_int_text(text : String) -> Int64 {
  let mut i = 0
  let negative = text.length() > 0 && char_at(text, 0) == '-'
  if negative || (text.length() > 0 && char_at(text, 0) == '+') {
    i = 1
  }
  let mut value = 0L
  while i < text.length() {
    let ch = char_at(text, i)
    if ch < '0' || ch > '9' {
      return 0L
    }
    value = value * 10L + (ch.to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn parse_double_text(text : String) -> Double {
  // Only the forms a proto default takes: an optional sign, digits, a decimal
  // point, and an optional exponent.
  let mut i = 0
  let negative = text.length() > 0 && char_at(text, 0) == '-'
  if negative || (text.length() > 0 && char_at(text, 0) == '+') {
    i = 1
  }
  let mut value = 0.0
  while i < text.length() && char_at(text, i) >= '0' && char_at(text, i) <= '9' {
    value = value * 10.0 +
      (char_at(text, i).to_int() - '0'.to_int()).to_double()
    i = i + 1
  }
  if i < text.length() && char_at(text, i) == '.' {
    i = i + 1
    let mut scale = 0.1
    while i < text.length() &&
          char_at(text, i) >= '0' &&
          char_at(text, i) <= '9' {
      value = value +
        (char_at(text, i).to_int() - '0'.to_int()).to_double() * scale
      scale = scale * 0.1
      i = i + 1
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn upper_char(ch : Char) -> Char {
  if ch >= 'a' && ch <= 'z' {
    (ch.to_int() - 32).to_char().unwrap_or(ch)
  } else {
    ch
  }
}

///|
/// The proto form of a runtime file descriptor.
pub fn to_file_descriptor_proto(
  file : @reflect.FileDescriptor,
) -> FileDescriptorProto {
  let messages : Array[DescriptorProto] = []
  for message in file.messages {
    messages.push(to_message_proto(message))
  }
  let enums : Array[EnumDescriptorProto] = []
  for item in file.enums {
    enums.push(to_enum_proto(item))
  }
  let services : Array[ServiceDescriptorProto] = []
  for service in file.services {
    let methods : Array[MethodDescriptorProto] = []
    for m in service.methods {
      methods.push({
        name: m.name,
        input_type: "." + m.input_type,
        output_type: "." + m.output_type,
        client_streaming: m.streaming_client,
        server_streaming: m.streaming_server,
      })
    }
    services.push({ name: service.name, methods, })
  }
  {
    name: file.path,
    package_name: file.package_name,
    syntax: match file.syntax {
      @reflect.Proto2 => "proto2"
      @reflect.Proto3 => "proto3"
      @reflect.Editions => "editions"
    },
    message_type: messages,
    enum_type: enums,
    service: services,
    extension: [],
    dependency: file.dependencies,
    public_dependency: [],
  }
}

///|
fn to_message_proto(message : @reflect.MessageDescriptor) -> DescriptorProto {
  let fields : Array[FieldDescriptorProto] = []
  for field in message.fields {
    fields.push(to_field_proto(field))
  }
  let nested : Array[DescriptorProto] = []
  for item in message.nested_messages {
    nested.push(to_message_proto(item))
  }
  let enums : Array[EnumDescriptorProto] = []
  for item in message.nested_enums {
    enums.push(to_enum_proto(item))
  }
  let oneofs : Array[OneofDescriptorProto] = []
  for oneof in message.oneofs {
    oneofs.push({ name: oneof.name, })
  }
  {
    name: message.name,
    field: fields,
    nested_type: nested,
    enum_type: enums,
    extension: [],
    oneof_decl: oneofs,
    reserved_range: message.reserved_ranges,
    reserved_name: message.reserved_names,
    extension_range: message.extension_ranges,
    map_entry: message.is_map_entry,
  }
}

///|
fn to_field_proto(field : @reflect.FieldDescriptor) -> FieldDescriptorProto {
  {
    name: field.name,
    number: field.number,
    label: field.cardinality.code(),
    type_code: field.kind.code(),
    type_name: match field.kind {
      @reflect.Message | @reflect.Group =>
        match field.message_type {
          Some(name) => Some("." + name)
          None => None
        }
      @reflect.Enum =>
        match field.enum_type {
          Some(name) => Some("." + name)
          None => None
        }
      _ => None
    },
    json_name: Some(field.json_name),
    default_value: None,
    oneof_index: field.oneof_index,
    proto3_optional: false,
    packed_off: !field.packed,
  }
}

///|
fn to_enum_proto(item : @reflect.EnumDescriptor) -> EnumDescriptorProto {
  let values : Array[EnumValueDescriptorProto] = []
  for value in item.values {
    values.push({ name: value.name, number: value.number, })
  }
  { name: item.name, value: values, }
}
