// Emitting MoonBit code from a file descriptor. Each message becomes a struct
// that holds a dynamic message, with typed accessors and a delegating
// `Message` implementation; each enum becomes a MoonBit enum with `code` and
// `of`.

///|
fn escape(text : String) -> String {
  let out = Buffer()
  for i in 0..<text.length() {
    let ch = text[i].to_int().to_char().unwrap_or('?')
    if ch == '\\' {
      out.write_string_utf8("\\\\")
    } else if ch == '"' {
      out.write_string_utf8("\\\"")
    } else if ch == '\n' {
      out.write_string_utf8("\\n")
    } else if ch == '\r' {
      out.write_string_utf8("\\r")
    } else if ch == '\t' {
      out.write_string_utf8("\\t")
    } else {
      out.write_string_utf8(ch.to_string())
    }
  }
  @utf8.decode(out.to_bytes()) catch {
    _ => ""
  }
}

///|
fn emit_features(f : @desc.Features) -> String {
  "@desc.Features::{ field_presence: " +
  f.field_presence.to_string() +
  ", enum_type: " +
  f.enum_type.to_string() +
  ", repeated_field_encoding: " +
  f.repeated_field_encoding.to_string() +
  ", message_encoding: " +
  f.message_encoding.to_string() +
  ", utf8_validation: " +
  f.utf8_validation.to_string() +
  ", json_format: " +
  f.json_format.to_string() +
  " }"
}

///|
fn emit_options(options : Array[(String, String)]) -> String {
  let out = Buffer()
  for pair in options {
    out.write_string_utf8(
      "(\"" + escape(pair.0) + "\", \"" + escape(pair.1) + "\"), ",
    )
  }
  "[" + utf8_of(out.to_bytes()) + "]"
}

///|
fn emit_field(
  field : @desc.FieldDescriptorProto,
  indentation : String,
) -> String {
  let type_name = match field.type_name {
    Some(name) => "Some(\"" + escape(name) + "\")"
    None => "None"
  }
  let json_name = match field.json_name {
    Some(name) => "Some(\"" + escape(name) + "\")"
    None => "None"
  }
  let default_value = match field.default_value {
    Some(value) => "Some(\"" + escape(value) + "\")"
    None => "None"
  }
  let oneof = match field.oneof_index {
    Some(index) => "Some(" + index.to_string() + ")"
    None => "None"
  }
  indentation +
  "@desc.FieldDescriptorProto::{ name: \"" +
  escape(field.name) +
  "\", number: " +
  field.number.to_string() +
  ", label: " +
  field.label.to_string() +
  ", type_code: " +
  field.type_code.to_string() +
  ", type_name: " +
  type_name +
  ", json_name: " +
  json_name +
  ", default_value: " +
  default_value +
  ", oneof_index: " +
  oneof +
  ", proto3_optional: " +
  (if field.proto3_optional { "true" } else { "false" }) +
  ", packed_off: " +
  (if field.packed_off { "true" } else { "false" }) +
  ", features: " +
  emit_features(field.features) +
  ", options: " +
  emit_options(field.options) +
  " }"
}

///|
fn emit_enum_proto(
  item : @desc.EnumDescriptorProto,
  indentation : String,
) -> String {
  let values = Buffer()
  for value in item.value {
    values.write_string_utf8(
      indentation +
      "  @desc.EnumValueDescriptorProto::{ name: \"" +
      escape(value.name) +
      "\", number: " +
      value.number.to_string() +
      " },\n",
    )
  }
  indentation +
  "@desc.EnumDescriptorProto::{\n" +
  indentation +
  "  name: \"" +
  escape(item.name) +
  "\",\n" +
  indentation +
  "  value: [\n" +
  utf8_of(values.to_bytes()) +
  indentation +
  "  ],\n" +
  indentation +
  "  features: " +
  emit_features(item.features) +
  ",\n" +
  indentation +
  "  options: " +
  emit_options(item.options) +
  ",\n" +
  indentation +
  "}"
}

///|
fn utf8_of(bytes : Bytes) -> String {
  @utf8.decode(bytes) catch {
    _ => ""
  }
}

///|
fn emit_message_proto(
  message : @desc.DescriptorProto,
  indentation : String,
) -> String {
  let inner = indentation + "  "
  let fields = Buffer()
  for field in message.field {
    fields.write_string_utf8(emit_field(field, inner + "  ") + ",\n")
  }
  let nested = Buffer()
  for item in message.nested_type {
    nested.write_string_utf8(emit_message_proto(item, inner + "  ") + ",\n")
  }
  let enums = Buffer()
  for item in message.enum_type {
    enums.write_string_utf8(emit_enum_proto(item, inner + "  ") + ",\n")
  }
  let extensions = Buffer()
  for field in message.extension {
    extensions.write_string_utf8(emit_field(field, inner + "  ") + ",\n")
  }
  let oneofs = Buffer()
  for oneof in message.oneof_decl {
    oneofs.write_string_utf8(
      inner +
      "  @desc.OneofDescriptorProto::{ name: \"" +
      escape(oneof.name) +
      "\" },\n",
    )
  }
  let reserved_ranges = Buffer()
  for range in message.reserved_range {
    reserved_ranges.write_string_utf8(
      "(" + range.0.to_string() + ", " + range.1.to_string() + "), ",
    )
  }
  let reserved_names = Buffer()
  for name in message.reserved_name {
    reserved_names.write_string_utf8("\"" + escape(name) + "\", ")
  }
  let extension_ranges = Buffer()
  for range in message.extension_range {
    extension_ranges.write_string_utf8(
      "(" + range.0.to_string() + ", " + range.1.to_string() + "), ",
    )
  }
  indentation +
  "@desc.DescriptorProto::{\n" +
  inner +
  "name: \"" +
  escape(message.name) +
  "\",\n" +
  inner +
  "field: [\n" +
  utf8_of(fields.to_bytes()) +
  inner +
  "],\n" +
  inner +
  "nested_type: [\n" +
  utf8_of(nested.to_bytes()) +
  inner +
  "],\n" +
  inner +
  "enum_type: [\n" +
  utf8_of(enums.to_bytes()) +
  inner +
  "],\n" +
  inner +
  "extension: [\n" +
  utf8_of(extensions.to_bytes()) +
  inner +
  "],\n" +
  inner +
  "oneof_decl: [\n" +
  utf8_of(oneofs.to_bytes()) +
  inner +
  "],\n" +
  inner +
  "reserved_range: [" +
  utf8_of(reserved_ranges.to_bytes()) +
  "],\n" +
  inner +
  "reserved_name: [" +
  utf8_of(reserved_names.to_bytes()) +
  "],\n" +
  inner +
  "extension_range: [" +
  utf8_of(extension_ranges.to_bytes()) +
  "],\n" +
  inner +
  "map_entry: " +
  (if message.map_entry { "true" } else { "false" }) +
  ",\n" +
  inner +
  "features: " +
  emit_features(message.features) +
  ",\n" +
  inner +
  "options: " +
  emit_options(message.options) +
  ",\n" +
  indentation +
  "}"
}

///|
fn emit_service_proto(
  service : @desc.ServiceDescriptorProto,
  indentation : String,
) -> String {
  let inner = indentation + "  "
  let methods = Buffer()
  for m in service.methods {
    methods.write_string_utf8(
      inner +
      "  @desc.MethodDescriptorProto::{ name: \"" +
      escape(m.name) +
      "\", input_type: \"" +
      escape(m.input_type) +
      "\", output_type: \"" +
      escape(m.output_type) +
      "\", client_streaming: " +
      (if m.client_streaming { "true" } else { "false" }) +
      ", server_streaming: " +
      (if m.server_streaming { "true" } else { "false" }) +
      " },\n",
    )
  }
  indentation +
  "@desc.ServiceDescriptorProto::{\n" +
  inner +
  "name: \"" +
  escape(service.name) +
  "\",\n" +
  inner +
  "methods: [\n" +
  utf8_of(methods.to_bytes()) +
  inner +
  "],\n" +
  indentation +
  "}"
}

///|
fn emit_file_proto(file : @desc.FileDescriptorProto) -> String {
  let messages = Buffer()
  for message in file.message_type {
    messages.write_string_utf8(emit_message_proto(message, "    ") + ",\n")
  }
  let enums = Buffer()
  for item in file.enum_type {
    enums.write_string_utf8(emit_enum_proto(item, "    ") + ",\n")
  }
  let services = Buffer()
  for item in file.service {
    services.write_string_utf8(emit_service_proto(item, "    ") + ",\n")
  }
  let extensions = Buffer()
  for field in file.extension {
    extensions.write_string_utf8(emit_field(field, "    ") + ",\n")
  }
  let dependencies = Buffer()
  for dependency in file.dependency {
    dependencies.write_string_utf8("\"" + escape(dependency) + "\", ")
  }
  "@desc.FileDescriptorProto::{\n" +
  "  name: \"" +
  escape(file.name) +
  "\",\n" +
  "  package_name: \"" +
  escape(file.package_name) +
  "\",\n" +
  "  syntax: \"" +
  escape(file.syntax) +
  "\",\n" +
  "  message_type: [\n" +
  utf8_of(messages.to_bytes()) +
  "  ],\n" +
  "  enum_type: [\n" +
  utf8_of(enums.to_bytes()) +
  "  ],\n" +
  "  service: [\n" +
  utf8_of(services.to_bytes()) +
  "  ],\n" +
  "  extension: [\n" +
  utf8_of(extensions.to_bytes()) +
  "  ],\n" +
  "  dependency: [" +
  utf8_of(dependencies.to_bytes()) +
  "],\n" +
  "  public_dependency: [],\n" +
  "  edition: " +
  (match file.edition {
    Some(text) => "Some(\"" + escape(text) + "\")"
    None => "None"
  }) +
  ",\n" +
  "  features: " +
  emit_features(file.features) +
  ",\n" +
  "  options: " +
  emit_options(file.options) +
  ",\n" +
  "}"
}

///|
/// MoonBit's reserved words cannot be method names, so a field called `type`
/// becomes `type_`. The descriptor keeps the proto name.
fn field_ident(name : String) -> String {
  let keywords : Array[String] = [
    "type", "package", "fn", "let", "mut", "match", "if", "else", "while", "for",
    "in", "return", "break", "continue", "true", "false", "async", "await", "impl",
    "trait", "struct", "enum", "pub", "priv", "extern", "test", "init", "const",
    "guard", "is", "as", "derive", "with", "raise", "catch", "throw", "try", "not",
    "and", "or", "null", "self", "Self", "super", "do", "loop", "method", "lazy",
    "defer", "sealed", "operator", "macro", "static", "virtual", "override", "final",
    "interface", "namespace", "using", "import", "export", "auto", "inline", "register",
    "signed", "unsigned", "volatile", "template", "this", "rethrow", "box", "typeof",
    "sizeof",
  ]
  // The reflective contract owns these names on every message, so a field with
  // one of them takes a suffix instead of shadowing the method.
  let reserved : Array[String] = [
    "descriptor", "message_type", "is_valid", "range", "range_extensions", "has",
    "clear", "get", "set", "mutable", "new_field", "which_oneof", "get_unknown",
    "set_unknown", "to_json", "from_json", "message", "new", "fresh",
  ]
  if keywords.contains(name) {
    name + "_"
  } else if reserved.contains(name) {
    name + "_field"
  } else {
    name
  }
}

///|
/// The MoonBit type of a scalar field's accessor.
fn scalar_type(kind : Int32) -> String? {
  match kind {
    1 => Some("Double")
    2 => Some("Double")
    3 => Some("Int64")
    4 => Some("UInt64")
    5 => Some("Int32")
    6 => Some("UInt64")
    7 => Some("UInt32")
    8 => Some("Bool")
    9 => Some("String")
    12 => Some("Bytes")
    13 => Some("UInt32")
    15 => Some("Int32")
    16 => Some("Int64")
    17 => Some("Int32")
    18 => Some("Int64")
    _ => None
  }
}

///|
fn zero_literal(kind : Int32) -> String {
  match kind {
    1 | 2 => "0.0"
    3 | 16 | 18 => "0L"
    4 | 6 => "0UL"
    5 | 15 | 17 | 14 => "0"
    7 | 13 => "0U"
    8 => "false"
    9 => "\"\""
    12 => "b\"\""
    _ => "0"
  }
}

///|
fn value_expr(kind : Int32, variable : String) -> String {
  match kind {
    1 | 2 => "@reflect.Double(" + variable + ")"
    3 | 16 | 18 => "@reflect.Int64(" + variable + ")"
    4 | 6 => "@reflect.Uint64(" + variable + ")"
    5 | 15 | 17 => "@reflect.Int32(" + variable + ")"
    7 | 13 => "@reflect.Uint32(" + variable + ")"
    8 => "@reflect.Bool(" + variable + ")"
    9 => "@reflect.String(" + variable + ")"
    12 => "@reflect.Bytes(" + variable + ")"
    14 => "@reflect.Enum(" + variable + ")"
    _ => "@reflect.Int32(" + variable + ")"
  }
}

///|
fn read_expr(kind : Int32, variable : String) -> String {
  match kind {
    1 | 2 => variable + ".float()"
    3 | 16 | 18 => variable + ".int()"
    4 | 6 => variable + ".uint()"
    5 | 15 | 17 => variable + ".int().to_int()"
    7 | 13 => variable + ".uint().to_uint()"
    8 => variable + ".bool()"
    9 => variable + ".string()"
    12 => variable + ".bytes()"
    14 => variable + ".enum_number()"
    _ => variable + ".int().to_int()"
  }
}

///|
fn wrapper_name(prefix : String, name : String) -> String {
  if prefix.length() == 0 {
    name
  } else {
    prefix + "_" + name
  }
}

///|
fn emit_enum(
  item : @desc.EnumDescriptorProto,
  prefix : String,
  buf : Buffer,
) -> Unit {
  let name = wrapper_name(prefix, item.name)
  buf.write_string_utf8("///|\npub(all) enum " + name + " {\n")
  // An open enum carries numbers it does not declare, so every generated enum
  // keeps a variant that can hold one.
  let has_unknown = true
  for value in item.value {
    buf.write_string_utf8("  " + value.name + "\n")
  }
  if has_unknown {
    buf.write_string_utf8("  Unknown(Int32)\n")
  }
  buf.write_string_utf8("}\n\n")
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::code(self : " +
    name +
    ") -> Int32 {\n  match self {\n",
  )
  for value in item.value {
    buf.write_string_utf8(
      "    " + value.name + " => " + value.number.to_string() + "\n",
    )
  }
  if has_unknown {
    buf.write_string_utf8("    Unknown(n) => n\n")
  }
  buf.write_string_utf8("  }\n}\n\n")
  buf.write_string_utf8(
    "///|\npub fn " + name + "::of(n : Int32) -> " + name + " {\n  match n {\n",
  )
  for value in item.value {
    buf.write_string_utf8(
      "    " + value.number.to_string() + " => " + value.name + "\n",
    )
  }
  buf.write_string_utf8("    _ => Unknown(n)\n  }\n}\n\n")
}

///|
fn emit_message(
  message : @reflect.MessageDescriptor,
  prefix : String,
  tag : String,
  buf : Buffer,
) -> Unit {
  let name = wrapper_name(prefix, message.name)
  let full = "\"" + escape(message.full_name) + "\""
  buf.write_string_utf8(
    "///|\npub struct " + name + " {\n  inner : @dynamic.Message\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::new() -> " +
    name +
    " {\n" +
    "  { inner: @dynamic.Message::new(find_message_" +
    tag +
    "(" +
    full +
    ")) }\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::message(self : " +
    name +
    ") -> @dynamic.Message {\n  self.inner\n}\n\n",
  )
  // Accessors.
  for field in message.fields {
    let field_name = field_ident(field.name)
    let number = field.number.to_string()
    if field.is_map {
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        field_name +
        "(self : " +
        name +
        ") -> &@reflect.MapField {\n  let f = field_of_" +
        tag +
        "(self.inner, " +
        number +
        ")\n  self.inner.mutable(f).map()\n}\n\n",
      )
    } else if field.cardinality == @reflect.Repeated {
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        field_name +
        "(self : " +
        name +
        ") -> &@reflect.ListField {\n  let f = field_of_" +
        tag +
        "(self.inner, " +
        number +
        ")\n  self.inner.mutable(f).list()\n}\n\n",
      )
    } else if field.kind == @reflect.Message || field.kind == @reflect.Group {
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        field_name +
        "(self : " +
        name +
        ") -> @reflect.Value {\n  let f = field_of_" +
        tag +
        "(self.inner, " +
        number +
        ")\n  if self.inner.has(f) { self.inner.get(f) } else { self.inner.mutable(f) }\n}\n\n",
      )
    } else {
      let type_name = scalar_type(field.kind.code()).unwrap_or("Int32")
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        field_name +
        "(self : " +
        name +
        ") -> " +
        type_name +
        " {\n  let f = field_of_" +
        tag +
        "(self.inner, " +
        number +
        ")\n  if self.inner.has(f) { " +
        read_expr(field.kind.code(), "self.inner.get(f)") +
        " } else { " +
        zero_literal(field.kind.code()) +
        " }\n}\n\n",
      )
    }
    if field.kind != @reflect.Message &&
      field.kind != @reflect.Group &&
      !field.is_map &&
      field.cardinality != @reflect.Repeated {
      let type_name = scalar_type(field.kind.code()).unwrap_or("Int32")
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::set_" +
        field_name +
        "(self : " +
        name +
        ", value : " +
        type_name +
        ") -> Unit {\n  self.inner.set(field_of_" +
        tag +
        "(self.inner, " +
        number +
        "), " +
        value_expr(field.kind.code(), "value") +
        ")\n}\n\n",
      )
    } else if field.kind == @reflect.Message || field.kind == @reflect.Group {
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::set_" +
        field_name +
        "(self : " +
        name +
        ", value : @reflect.Value) -> Unit {\n  self.inner.set(field_of_" +
        tag +
        "(self.inner, " +
        number +
        "), value)\n}\n\n",
      )
    }
  }
  // Oneof accessors: an enum over the members, a reader and a writer.
  for index in 0..<message.oneofs.length() {
    let oneof = message.oneofs[index]
    if !oneof.synthetic && oneof.field_numbers.length() > 0 {
      emit_oneof(message, name, tag, oneof, buf)
    }
  }
  // JSON, through the shared mapping.
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::to_json(self : " +
    name +
    ") -> String raise @json.Refused {\n  @json.encode(self)\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::from_json(text : String) -> " +
    name +
    " raise @json.Refused {\n  let message = " +
    name +
    "::new()\n  @json.decode(text, message)\n  message\n}\n\n",
  )
  // Message implementation, delegating to the dynamic message.
  let signatures : Array[String] = [
    "fn descriptor(self) -> @reflect.MessageDescriptor", "fn message_type(self) -> &@reflect.MessageType",
    "fn is_valid(self) -> Bool", "fn range(self, f : (@reflect.FieldDescriptor, @reflect.Value) -> Bool) -> Unit",
    "fn range_extensions(self, f : (@reflect.FieldDescriptor, @reflect.Value) -> Bool) -> Unit",
    "fn has(self, field : @reflect.FieldDescriptor) -> Bool", "fn clear(self, field : @reflect.FieldDescriptor) -> Unit",
    "fn get(self, field : @reflect.FieldDescriptor) -> @reflect.Value", "fn set(self, field : @reflect.FieldDescriptor, value : @reflect.Value) -> Unit",
    "fn mutable(self, field : @reflect.FieldDescriptor) -> @reflect.Value", "fn new_field(self, field : @reflect.FieldDescriptor) -> @reflect.Value",
    "fn which_oneof(self, oneof : @reflect.OneofDescriptor) -> Int32?", "fn get_unknown(self) -> @reflect.RawFields",
    "fn set_unknown(self, raw : @reflect.RawFields) -> Unit",
  ]
  let bodies : Array[String] = [
    "self.inner.descriptor()",
    "let _ = self\n  " + lower_name(name) + "_type",
    "self.inner.is_valid()",
    "self.inner.range(f)",
    "self.inner.range_extensions(f)",
    "self.inner.has(field)",
    "self.inner.clear(field)",
    "self.inner.get(field)",
    "self.inner.set(field, value)",
    "self.inner.mutable(field)",
    "self.inner.new_field(field)",
    "self.inner.which_oneof(oneof)",
    "self.inner.get_unknown()",
    "self.inner.set_unknown(raw)",
  ]
  for i in 0..<signatures.length() {
    buf.write_string_utf8(
      "pub impl @reflect.Message for " +
      name +
      " with " +
      signatures[i] +
      " {\n  " +
      bodies[i] +
      "\n}\n\n",
    )
  }
  buf.write_string_utf8(
    "///|\npub extend " +
    name +
    " with @reflect.Message::{descriptor, message_type, is_valid, range, range_extensions, has, clear, get, set, mutable, new_field, which_oneof, get_unknown, set_unknown}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Fresh for " +
    name +
    " with fn fresh(_self) -> " +
    name +
    " {\n  " +
    name +
    "::new()\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub extend " + name + " with @reflect.Fresh::{fresh}\n\n",
  )
  // Message type.
  buf.write_string_utf8(
    "///|\npub struct " + name + "Type {\n  marker : Unit\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "Type::new() -> " +
    name +
    "Type {\n  { marker: () }\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.MessageType for " +
    name +
    "Type with fn new_message(_self) -> &@reflect.Message {\n  (" +
    name +
    "::new() as &@reflect.Message)\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.MessageType for " +
    name +
    "Type with fn zero(_self) -> &@reflect.Message {\n  (" +
    name +
    "::new() as &@reflect.Message)\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.MessageType for " +
    name +
    "Type with fn descriptor(_self) -> @reflect.MessageDescriptor {\n  find_message_" +
    tag +
    "(" +
    full +
    ")\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub extend " +
    name +
    "Type with @reflect.MessageType::{new_message, zero, descriptor}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub let " +
    lower_name(name) +
    "_type : &@reflect.MessageType = (" +
    name +
    "Type::new() as &@reflect.MessageType)\n\n",
  )
}

///|
fn lower_name(name : String) -> String {
  if name.length() == 0 {
    name
  } else {
    let first = name[0].to_int().to_char().unwrap_or('a')
    let lower = if first >= 'A' && first <= 'Z' {
      (first.to_int() + 32).to_char().unwrap_or(first)
    } else {
      first
    }
    lower.to_string() + name[1:].to_owned()
  }
}

///|
fn upper_first(name : String) -> String {
  if name.length() == 0 {
    return "Unnamed"
  }
  let first = name[0].to_int().to_char().unwrap_or('A')
  let upper = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).to_char().unwrap_or(first)
  } else {
    first
  }
  upper.to_string() + name[1:name.length()].to_owned()
}

///|
fn oneof_variant(field : @reflect.FieldDescriptor) -> String {
  upper_first(field.name)
}

///|
fn emit_oneof(
  message : @reflect.MessageDescriptor,
  name : String,
  tag : String,
  oneof : @reflect.OneofDescriptor,
  buf : Buffer,
) -> Unit {
  let members : Array[@reflect.FieldDescriptor] = []
  for number in oneof.field_numbers {
    match message.field_by_number(number) {
      Some(field) => members.push(field)
      None => ()
    }
  }
  let choice = name + "_" + upper_first(oneof.name)
  buf.write_string_utf8("///|\npub(all) enum " + choice + " {\n")
  for field in members {
    let payload = if field.kind == @reflect.Message ||
      field.kind == @reflect.Group ||
      field.kind == @reflect.Enum {
      "@reflect.Value"
    } else {
      scalar_type(field.kind.code()).unwrap_or("Int32")
    }
    buf.write_string_utf8("  " + oneof_variant(field) + "(" + payload + ")\n")
  }
  buf.write_string_utf8("  No" + upper_first(oneof.name) + "\n}\n\n")
  // Reader.
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::" +
    field_ident(oneof.name) +
    "(self : " +
    name +
    ") -> " +
    choice +
    " {\n  let oneof = oneof_of_" +
    tag +
    "(self.inner, \"" +
    escape(oneof.name) +
    "\")\n  match self.inner.which_oneof(oneof) {\n",
  )
  for field in members {
    let payload = if field.kind == @reflect.Message ||
      field.kind == @reflect.Group ||
      field.kind == @reflect.Enum {
      "@reflect.Value"
    } else {
      scalar_type(field.kind.code()).unwrap_or("Int32")
    }
    let expr = if payload == "@reflect.Value" {
      "self.inner.get(field)"
    } else {
      read_expr(field.kind.code(), "self.inner.get(field)")
    }
    buf.write_string_utf8(
      "    Some(" +
      field.number.to_string() +
      ") => {\n      let field = field_of_" +
      tag +
      "(self.inner, " +
      field.number.to_string() +
      ")\n      " +
      choice +
      "::" +
      oneof_variant(field) +
      "(" +
      expr +
      ")\n    }\n",
    )
  }
  buf.write_string_utf8(
    "    _ => " + choice + "::No" + upper_first(oneof.name) + "\n  }\n}\n\n",
  )
  // Writer.
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::set_" +
    field_ident(oneof.name) +
    "(self : " +
    name +
    ", value : " +
    choice +
    ") -> Unit {\n  match value {\n",
  )
  for field in members {
    let payload = if field.kind == @reflect.Message ||
      field.kind == @reflect.Group ||
      field.kind == @reflect.Enum {
      "@reflect.Value"
    } else {
      scalar_type(field.kind.code()).unwrap_or("Int32")
    }
    let bound = if payload == "@reflect.Value" {
      "item"
    } else {
      value_expr(field.kind.code(), "item")
    }
    buf.write_string_utf8(
      "    " +
      choice +
      "::" +
      oneof_variant(field) +
      "(item) =>\n      self.inner.set(field_of_" +
      tag +
      "(self.inner, " +
      field.number.to_string() +
      "), " +
      bound +
      ")\n",
    )
  }
  buf.write_string_utf8(
    "    _" +
    " => self.inner.clear(field_of_" +
    tag +
    "(self.inner, " +
    members[0].number.to_string() +
    "))\n  }\n}\n\n",
  )
}

///|
fn emit_messages(
  messages : Array[@reflect.MessageDescriptor],
  prefix : String,
  tag : String,
  buf : Buffer,
) -> Unit {
  for message in messages {
    let name = wrapper_name(prefix, message.name)
    emit_message(message, prefix, tag, buf)
    emit_messages(message.nested_messages, name, tag, buf)
  }
}

///|
fn has_field(messages : Array[@reflect.MessageDescriptor]) -> Bool {
  for message in messages {
    if message.fields.length() > 0 {
      return true
    }
    if has_field(message.nested_messages) {
      return true
    }
  }
  false
}

///|
fn has_real_oneof(messages : Array[@reflect.MessageDescriptor]) -> Bool {
  for message in messages {
    for oneof in message.oneofs {
      if !oneof.synthetic && oneof.field_numbers.length() > 0 {
        return true
      }
    }
    if has_real_oneof(message.nested_messages) {
      return true
    }
  }
  false
}

///|
/// A file's stem with everything but letters and digits folded to `_`, so its
/// package-level helpers cannot collide with another file's.
fn file_tag(path : String) -> String {
  let out = Buffer()
  for i in 0..<path.length() {
    let ch = path[i].to_int().to_char().unwrap_or('x')
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') {
      out.write_string_utf8(ch.to_string())
    } else {
      out.write_string_utf8("_")
    }
  }
  utf8_of(out.to_bytes())
}

///|
/// Generate the MoonBit source for one file descriptor.
pub fn generate_source(
  file : @desc.FileDescriptorProto,
) -> String raise Refused {
  let built = @desc.build_file(file) catch {
    _ => raise Desc(@desc.Refused::Syntax(file.name))
  }
  let buf = Buffer()
  buf.write_string_utf8(
    "// Generated by protoc-gen-mbt from " +
    escape(file.name) +
    ". Do not edit.\n\n",
  )
  let tag = file_tag(file.name)
  buf.write_string_utf8(
    "pub fn file_descriptor_" +
    tag +
    "() -> @reflect.FileDescriptor raise @desc.Refused {\n  @desc.build_file(" +
    emit_file_proto(file) +
    ")\n}\n\n",
  )
  buf.write_string_utf8(
    "let cached_" +
    tag +
    " : @reflect.FileDescriptor = file_descriptor_" +
    tag +
    "() catch {\n  _ => abort(\"moonproto: descriptor could not be built\")\n}\n\n",
  )
  buf.write_string_utf8(
    "fn find_in_" +
    tag +
    "(items : Array[@reflect.MessageDescriptor], name : String) -> @reflect.MessageDescriptor? {\n  for item in items {\n    if item.full_name == name {\n      return Some(item)\n    }\n    match find_in_" +
    tag +
    "(item.nested_messages, name) {\n      Some(found) => return Some(found)\n      None => ()\n    }\n  }\n  None\n}\n\n",
  )
  buf.write_string_utf8(
    "fn find_message_" +
    tag +
    "(name : String) -> @reflect.MessageDescriptor {\n  match find_in_" +
    tag +
    "(cached_" +
    tag +
    ".messages, name) {\n    Some(found) => found\n    None => abort(\"moonproto: missing \" + name)\n  }\n}\n\n",
  )
  if has_field(built.messages) {
    buf.write_string_utf8(
      "fn field_of_" +
      tag +
      "(message : @dynamic.Message, number : Int32) -> @reflect.FieldDescriptor {\n  match message.descriptor().field_by_number(number) {\n    Some(field) => field\n    None => abort(\"moonproto: missing field \" + number.to_string())\n  }\n}\n\n",
    )
  }
  if has_real_oneof(built.messages) {
    buf.write_string_utf8(
      "fn oneof_of_" +
      tag +
      "(message : @dynamic.Message, name : String) -> @reflect.OneofDescriptor {\n  for item in message.descriptor().oneofs {\n    if item.name == name {\n      return item\n    }\n  }\n  abort(\"moonproto: missing oneof \" + name)\n}\n\n",
    )
  }
  for item in built.enums {
    emit_enum(
      {
        name: item.name,
        value: {
          let values : Array[@desc.EnumValueDescriptorProto] = []
          for value in item.values {
            values.push({ name: value.name, number: value.number, })
          }
          values
        },
        features: @desc.features_auto,
        options: [],
      },
      "",
      buf,
    )
  }
  emit_messages(built.messages, "", tag, buf)
  utf8_of(buf.to_bytes())
}

///|
fn output_path(path : String) -> String {
  let stem = if path.has_suffix(".proto") {
    path[:path.length() - 6].to_owned()
  } else {
    path
  }
  stem + ".mbt"
}

///|
/// The protoc plugin entry point: a serialized request in, a serialized
/// response out.
pub fn plugin_main(request_bytes : Bytes) -> Bytes {
  let request = decode_request(request_bytes) catch {
    _ => return encode_error("could not decode the request")
  }
  let files : Array[(String, String)] = []
  for file in request.proto_file {
    let mut wanted = false
    for name in request.files_to_generate {
      if name == file.name {
        wanted = true
      }
    }
    if wanted {
      let source = generate_source(file) catch {
        _ => return encode_error("could not generate " + file.name)
      }
      files.push((output_path(file.name), source))
    }
  }
  encode_response(files, None) catch {
    _ => b""
  }
}

///|
fn encode_error(text : String) -> Bytes {
  encode_response([], Some(text)) catch {
    _ => b""
  }
}
