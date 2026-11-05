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
  ", extendee: " +
  (match field.extendee {
    Some(name) => "Some(\"" + escape(name) + "\")"
    None => "None"
  }) +
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
/// A generated enum: the variants, `code` and `of`. An open enum carries numbers
/// it does not declare, so every generated enum keeps a variant that can hold
/// one.
fn emit_enum(
  item : @reflect.EnumDescriptor,
  prefix : String,
  buf : Buffer,
) -> Unit {
  let name = type_ident(wrapper_name(prefix, item.name))
  buf.write_string_utf8("///|\npub(all) enum " + name + " {\n")
  for value in item.values {
    buf.write_string_utf8("  " + value.name + "\n")
  }
  buf.write_string_utf8("  Unknown(Int32)\n}\n\n")
  buf.write_string_utf8(
    "///|\npub fn " +
    name +
    "::code(self : " +
    name +
    ") -> Int32 {\n  match self {\n",
  )
  for value in item.values {
    buf.write_string_utf8(
      "    " + value.name + " => " + value.number.to_string() + "\n",
    )
  }
  buf.write_string_utf8("    Unknown(n) => n\n  }\n}\n\n")
  buf.write_string_utf8(
    "///|\npub fn " + name + "::of(n : Int32) -> " + name + " {\n  match n {\n",
  )
  for value in item.values {
    buf.write_string_utf8(
      "    " + value.number.to_string() + " => " + value.name + "\n",
    )
  }
  buf.write_string_utf8("    _ => Unknown(n)\n  }\n}\n\n")
}

///|
/// Emit every message of a file, each followed by the enums and messages nested
/// in it. A map entry is skipped: the field that uses it is a `Map`, so no
/// message of its own is needed.
fn emit_messages(
  messages : Array[@reflect.MessageDescriptor],
  prefix : String,
  tag : String,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  for message in messages {
    if message.is_map_entry {
      continue
    }
    let name = type_ident(wrapper_name(prefix, message.name))
    emit_message(message, prefix, tag, naming, buf)
    for item in message.nested_enums {
      emit_enum(item, name, buf)
    }
    emit_messages(message.nested_messages, name, tag, naming, buf)
  }
}

///|
/// Generate the MoonBit source for one file descriptor, resolving the types the
/// file refers to against its own declarations only.
pub fn generate_source(
  file : @desc.FileDescriptorProto,
) -> String raise Refused {
  let symbols = Symbols::new()
  symbols.add_file(file)
  generate_file(file, symbols)
}

///|
/// Generate one file, resolving the types it refers to against every file of the
/// request, so a reference to another file's message names the right type.
pub fn generate_source_with(
  file : @desc.FileDescriptorProto,
  symbols : Symbols,
) -> String raise Refused {
  generate_file(file, symbols)
}

///|
fn generate_file(
  file : @desc.FileDescriptorProto,
  symbols : Symbols,
) -> String raise Refused {
  let built = @desc.build_file(file) catch {
    _ => raise Desc(@desc.Refused::Syntax(file.name))
  }
  let naming = Naming::new(file_dir(file.name), symbols)
  let tag = file_tag(file.name)
  let buf = Buffer()
  buf.write_string_utf8(
    "// Generated by protoc-gen-mbt from " +
    escape(file.name) +
    ". Do not edit.\n\n",
  )
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
  for item in built.enums {
    emit_enum(item, "", buf)
  }
  emit_messages(built.messages, "", tag, naming, buf)
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
  let symbols = Symbols::new()
  for file in request.proto_file {
    symbols.add_file(file)
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
      let source = generate_source_with(file, symbols) catch {
        err =>
          return encode_error(
            "could not generate " + file.name + ": " + err.to_string(),
          )
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
