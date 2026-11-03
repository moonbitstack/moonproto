// The JSON mapping: names, the 64-bit integers as strings, enums by name,
// bytes as base64, maps as objects, and the well-known forms that are not a
// plain object.

///|
/// How a message is written as JSON.
pub(all) struct MarshalOptions {
  multiline : Bool
  indent : String
  allow_partial : Bool
  use_proto_names : Bool
  use_enum_numbers : Bool
  emit_unpopulated : Bool
  emit_default_values : Bool
}

///|
pub let marshal_options : MarshalOptions = {
  multiline: false,
  indent: "",
  allow_partial: false,
  use_proto_names: false,
  use_enum_numbers: false,
  emit_unpopulated: false,
  emit_default_values: false,
}

///|
/// How a message is read from JSON.
pub(all) struct UnmarshalOptions {
  allow_partial : Bool
  discard_unknown : Bool
  recursion_limit : Int32
}

///|
pub let unmarshal_options : UnmarshalOptions = {
  allow_partial: false,
  discard_unknown: false,
  recursion_limit: 10000,
}

///|
/// A JSON refusal.
pub(all) suberror Refused {
  Syntax(String)
  UnknownField(String)
  BadValue(String)
  BadBase64(String)
  Recursion(Int32)
  NoType(String)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Syntax(message) => logger.write_string("syntax: " + message)
    UnknownField(name) => logger.write_string("unknown field " + name)
    BadValue(name) => logger.write_string("bad value for " + name)
    BadBase64(name) => logger.write_string("bad base64 for " + name)
    Recursion(limit) =>
      logger.write_string("recursion limit " + limit.to_string())
    NoType(name) => logger.write_string("no type registered for " + name)
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// The JSON text of `message`.
pub fn[M : @reflect.Message] encode(
  message : M,
  marshal_options~ : MarshalOptions = marshal_options,
) -> String raise Refused {
  let value = message_to_json(message as &@reflect.Message, marshal_options, 0)
  if marshal_options.multiline || marshal_options.indent.length() > 0 {
    let width = if marshal_options.indent.length() > 0 {
      marshal_options.indent.length()
    } else {
      2
    }
    value.stringify(indent=width)
  } else {
    value.stringify()
  }
}

///|
/// A message as a `Json` value, so it composes with core's JSON layer.
pub fn[M : @reflect.Message] to_json(
  message : M,
  marshal_options~ : MarshalOptions = marshal_options,
) -> @cjson.Json raise Refused {
  message_to_json(message as &@reflect.Message, marshal_options, 0)
}

///|
/// Read JSON text into `message`, replacing its contents.
pub fn[M : @reflect.Message] decode(
  text : StringView,
  message : M,
  unmarshal_options~ : UnmarshalOptions = unmarshal_options,
) -> Unit raise Refused {
  let value = @cjson.parse(text, preserve_number_repr=true) catch {
    _ => raise Syntax("not JSON")
  }
  from_json(message, value, unmarshal_options~)
}

///|
/// Read a `Json` value into `message`.
pub fn[M : @reflect.Message] from_json(
  message : M,
  value : @cjson.Json,
  unmarshal_options~ : UnmarshalOptions = unmarshal_options,
) -> Unit raise Refused {
  proto_reset(message)
  message_from_json(message as &@reflect.Message, value, unmarshal_options, 0)
}

///|
fn[M : @reflect.Message] proto_reset(message : M) -> Unit {
  let desc = message.descriptor()
  for field in desc.fields {
    message.clear(field)
  }
}

///|
fn message_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  if depth > 100 {
    raise Recursion(100)
  }
  let full = message.descriptor().full_name
  match full {
    "google.protobuf.Any" => any_to_json(message, opts, depth)
    "google.protobuf.Timestamp" => timestamp_to_json(message)
    "google.protobuf.Duration" => duration_to_json(message)
    "google.protobuf.BoolValue"
    | "google.protobuf.Int32Value"
    | "google.protobuf.Int64Value"
    | "google.protobuf.UInt32Value"
    | "google.protobuf.UInt64Value"
    | "google.protobuf.FloatValue"
    | "google.protobuf.DoubleValue"
    | "google.protobuf.StringValue"
    | "google.protobuf.BytesValue" => wrapper_to_json(message, opts)
    "google.protobuf.FieldMask" => field_mask_to_json(message)
    "google.protobuf.Empty" => @cjson.Json::empty_object()
    "google.protobuf.Struct" => struct_to_json(message, opts, depth)
    "google.protobuf.Value" => value_to_json(message, opts, depth)
    "google.protobuf.ListValue" => list_value_to_json(message, opts, depth)
    _ => object_to_json(message, opts, depth)
  }
}

///|
fn object_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let desc = message.descriptor()
  let fields : Map[String, @cjson.Json] = Map([])
  for field in desc.fields {
    let name = if opts.use_proto_names { field.name } else { field.json_name }
    if field.is_map {
      let mut emit = opts.emit_unpopulated || opts.emit_default_values
      if !emit && message.has(field) {
        emit = message.get(field).map().length() > 0
      }
      if emit {
        fields.set(name, map_to_json(field, message, opts, depth))
      }
    } else if field.is_list() {
      let mut emit = opts.emit_unpopulated || opts.emit_default_values
      if !emit && message.has(field) {
        emit = message.get(field).list().length() > 0
      }
      if emit {
        fields.set(name, list_to_json(field, message, opts, depth))
      }
    } else if message.has(field) {
      fields.set(name, singular_to_json(field, message.get(field), opts, depth))
    } else if opts.emit_unpopulated || opts.emit_default_values {
      fields.set(name, default_to_json(field, opts, depth))
    }
  }
  // An extension is keyed by its full name in brackets, which is how the JSON
  // form keeps it from colliding with a declared field.
  let extensions : Array[@reflect.FieldDescriptor] = []
  message.range_extensions(fn(field, _value) {
    extensions.push(field)
    true
  })
  for field in extensions {
    let name = "[" + field.full_name + "]"
    if field.is_list() {
      fields.set(name, list_to_json(field, message, opts, depth))
    } else {
      fields.set(name, singular_to_json(field, message.get(field), opts, depth))
    }
  }
  @cjson.Json::object(fields)
}

///|
fn map_to_json(
  field : @reflect.FieldDescriptor,
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let out : Map[String, @cjson.Json] = Map([])
  let entries : Array[(@reflect.MapKey, @reflect.Value)] = []
  if message.has(field) {
    message
    .get(field)
    .map()
    .range(fn(key, value) {
      entries.push((key, value))
      true
    })
  }
  match field.map_value_field {
    Some(value_field) =>
      for entry in entries {
        out.set(
          map_key_to_string(entry.0),
          singular_to_json(value_field, entry.1, opts, depth),
        )
      }
    None => ()
  }
  @cjson.Json::object(out)
}

///|
fn list_to_json(
  field : @reflect.FieldDescriptor,
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let items : Array[@cjson.Json] = []
  if message.has(field) {
    let list = message.get(field).list()
    for i in 0..<list.length() {
      items.push(singular_to_json(field, list.get(i), opts, depth))
    }
  }
  @cjson.Json::array(items)
}

///|
fn default_to_json(
  field : @reflect.FieldDescriptor,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let value = @reflect.default_for(field)
  if field.kind.is_message() {
    @cjson.Json::null()
  } else {
    singular_to_json(field, value, opts, depth)
  }
}

///|
fn singular_to_json(
  field : @reflect.FieldDescriptor,
  value : @reflect.Value,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  match field.kind {
    @reflect.Bool => @cjson.Json::boolean(value.bool())
    @reflect.String => @cjson.Json::string(value.string())
    @reflect.Bytes => @cjson.Json::string(@base64.encode(value.bytes()))
    @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 =>
      number_json(value.int())
    @reflect.Uint32 | @reflect.Fixed32 =>
      number_json(value.uint().reinterpret_as_int64())
    @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>
      @cjson.Json::string(value.int().to_string())
    @reflect.Uint64 | @reflect.Fixed64 =>
      @cjson.Json::string(value.uint().to_string())
    @reflect.Float | @reflect.Double => float_json(value.float())
    @reflect.Enum => enum_to_json(field, value.enum_number(), opts)
    @reflect.Message | @reflect.Group =>
      message_to_json(value.message(), opts, depth + 1)
  }
}

///|
fn number_json(value : Int64) -> @cjson.Json {
  @cjson.Json::number(value.to_double(), repr=value.to_string())
}

///|
fn float_json(value : Double) -> @cjson.Json {
  if value.is_nan() {
    @cjson.Json::string("NaN")
  } else if value.is_inf() {
    if value > 0.0 {
      @cjson.Json::string("Infinity")
    } else {
      @cjson.Json::string("-Infinity")
    }
  } else {
    @cjson.Json::number(value, repr=value.to_string())
  }
}

///|
fn enum_to_json(
  field : @reflect.FieldDescriptor,
  number : Int32,
  opts : MarshalOptions,
) -> @cjson.Json {
  if opts.use_enum_numbers {
    return number_json(number.to_int64())
  }
  match field.enum_type {
    Some(name) =>
      match @reflect.global_files.find_enum_by_name(name) {
        Some(desc) =>
          match desc.value_by_number(number) {
            Some(value) => @cjson.Json::string(value.name)
            None => number_json(number.to_int64())
          }
        None => number_json(number.to_int64())
      }
    None => number_json(number.to_int64())
  }
}

///|
fn map_key_to_string(key : @reflect.MapKey) -> String {
  match key {
    @reflect.Bool(value) => if value { "true" } else { "false" }
    @reflect.Int32(value) => value.to_string()
    @reflect.Int64(value) => value.to_string()
    @reflect.Uint32(value) => value.to_string()
    @reflect.Uint64(value) => value.to_string()
    @reflect.String(value) => value
  }
}

// -- well-known forms -------------------------------------------------------

///|
fn wrapper_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
) -> @cjson.Json raise Refused {
  match message.descriptor().field_by_number(1) {
    Some(field) =>
      if message.has(field) {
        singular_to_json(field, message.get(field), opts, 1)
      } else {
        default_to_json(field, opts, 1)
      }
    None => @cjson.Json::null()
  }
}

///|
fn two_numbers(message : &@reflect.Message) -> (Int64, Int32) {
  let desc = message.descriptor()
  let seconds = match desc.field_by_number(1) {
    Some(field) =>
      if message.has(field) {
        message.get(field).int()
      } else {
        0L
      }
    None => 0L
  }
  let nanos = match desc.field_by_number(2) {
    Some(field) =>
      if message.has(field) {
        message.get(field).int().to_int()
      } else {
        0
      }
    None => 0
  }
  (seconds, nanos)
}

///|
fn timestamp_to_json(message : &@reflect.Message) -> @cjson.Json {
  let (seconds, nanos) = two_numbers(message)
  @cjson.Json::string(format_timestamp(seconds, nanos))
}

///|
fn duration_to_json(message : &@reflect.Message) -> @cjson.Json {
  let (seconds, nanos) = two_numbers(message)
  @cjson.Json::string(format_duration(seconds, nanos))
}

///|
fn field_mask_to_json(message : &@reflect.Message) -> @cjson.Json {
  let desc = message.descriptor()
  match desc.field_by_number(1) {
    Some(field) =>
      if message.has(field) {
        let list = message.get(field).list()
        let parts : Array[String] = []
        for i in 0..<list.length() {
          parts.push(list.get(i).string())
        }
        @cjson.Json::string(join_strings(parts))
      } else {
        @cjson.Json::string("")
      }
    None => @cjson.Json::string("")
  }
}

///|
fn join_strings(parts : Array[String]) -> String {
  let mut text = ""
  let mut first = true
  for part in parts {
    if !first {
      text = text + ","
    }
    text = text + part
    first = false
  }
  text
}

///|
fn any_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let desc = message.descriptor()
  let type_field = desc.field_by_number(1)
  let value_field = desc.field_by_number(2)
  let type_url = match type_field {
    Some(field) =>
      if message.has(field) {
        message.get(field).string()
      } else {
        ""
      }
    None => ""
  }
  if type_url.length() == 0 {
    return @cjson.Json::empty_object()
  }
  let body = match value_field {
    Some(field) =>
      if message.has(field) {
        message.get(field).bytes()
      } else {
        b""
      }
    None => b""
  }
  let name = type_url_after_slash(type_url)
  let out : Map[String, @cjson.Json] = Map([])
  out.set("@type", @cjson.Json::string(type_url))
  match @reflect.global_types.find_message_by_name(name) {
    Some(message_type) => {
      let nested = message_type.new_message()
      @proto.decode(body, nested) catch {
        _ => raise BadValue("Any.value")
      }
      match message_to_json(nested, opts, depth + 1) {
        @cjson.Json::Object(fields) =>
          for pair in fields {
            out.set(pair.0, pair.1)
          }
        _ => ()
      }
    }
    None => raise NoType(name)
  }
  @cjson.Json::object(out)
}

///|
fn type_url_after_slash(url : String) -> String {
  let mut start = 0
  for i in 0..<url.length() {
    if url[i] == '/' {
      start = i + 1
    }
  }
  url[start:].to_owned()
}

// -- decoding ---------------------------------------------------------------

///|
fn message_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if depth > opts.recursion_limit {
    raise Recursion(opts.recursion_limit)
  }
  let full = message.descriptor().full_name
  match full {
    "google.protobuf.Any" => any_from_json(message, value, opts, depth)
    "google.protobuf.Timestamp" => timestamp_from_json(message, value)
    "google.protobuf.Duration" => duration_from_json(message, value)
    "google.protobuf.BoolValue"
    | "google.protobuf.Int32Value"
    | "google.protobuf.Int64Value"
    | "google.protobuf.UInt32Value"
    | "google.protobuf.UInt64Value"
    | "google.protobuf.FloatValue"
    | "google.protobuf.DoubleValue"
    | "google.protobuf.StringValue"
    | "google.protobuf.BytesValue" => wrapper_from_json(message, value, opts)
    "google.protobuf.FieldMask" => field_mask_from_json(message, value)
    "google.protobuf.Empty" => ()
    "google.protobuf.Struct" => struct_from_json(message, value, opts, depth)
    "google.protobuf.Value" => value_from_json(message, value, opts, depth)
    "google.protobuf.ListValue" =>
      list_value_from_json(message, value, opts, depth)
    _ => object_from_json(message, value, opts, depth)
  }
}

///|
fn object_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let object = match value {
    @cjson.Json::Object(fields) => fields
    @cjson.Json::Null => return
    _ => raise Syntax("expected an object")
  }
  for pair in object {
    let name = pair.0
    if name.has_prefix("[") && name.has_suffix("]") {
      let qualified = name[1:name.length() - 1].to_owned()
      match @reflect.global_types.find_extension_by_name(qualified) {
        Some(extension) => {
          let field = extension.descriptor()
          field_from_json(message, field, pair.1, opts, depth)
        }
        None => if !opts.discard_unknown { raise UnknownField(name) }
      }
      continue
    }
    let field = match message.descriptor().field_by_json_name(name) {
      Some(field) => Some(field)
      None => message.descriptor().field_by_name(name)
    }
    match field {
      Some(found) => field_from_json(message, found, pair.1, opts, depth)
      None => if !opts.discard_unknown { raise UnknownField(name) }
    }
  }
}

// -- Struct, Value and ListValue --------------------------------------------
//
// These three carry arbitrary JSON rather than a fixed message shape: Struct is
// an object, ListValue an array, and Value whichever JSON kind its oneof holds.

///|
fn message_field_by_name(
  message : &@reflect.Message,
  name : String,
) -> @reflect.FieldDescriptor? {
  message.descriptor().field_by_name(name)
}

///|
fn struct_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let out : Map[String, @cjson.Json] = Map([])
  match message_field_by_name(message, "fields") {
    Some(field) =>
      if message.has(field) {
        let entries : Array[(@reflect.MapKey, @reflect.Value)] = []
        message
        .get(field)
        .map()
        .range(fn(key, value) {
          entries.push((key, value))
          true
        })
        for entry in entries {
          out.set(
            map_key_to_string(entry.0),
            value_to_json(entry.1.message(), opts, depth),
          )
        }
      }
    None => ()
  }
  @cjson.Json::object(out)
}

///|
fn list_value_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  let items : Array[@cjson.Json] = []
  match message_field_by_name(message, "values") {
    Some(field) =>
      if message.has(field) {
        let list = message.get(field).list()
        for i in 0..<list.length() {
          items.push(value_to_json(list.get(i).message(), opts, depth))
        }
      }
    None => ()
  }
  @cjson.Json::array(items)
}

///|
fn value_to_json(
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> @cjson.Json raise Refused {
  for field in message.descriptor().fields {
    if message.has(field) {
      let value = message.get(field)
      return match field.name {
        "null_value" => @cjson.Json::null()
        "number_value" => float_json(value.float())
        "string_value" => @cjson.Json::string(value.string())
        "bool_value" => @cjson.Json::boolean(value.bool())
        "struct_value" => struct_to_json(value.message(), opts, depth)
        "list_value" => list_value_to_json(value.message(), opts, depth)
        _ => @cjson.Json::null()
      }
    }
  }
  // An unset Value is JSON null, not an error.
  @cjson.Json::null()
}

///|
fn struct_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let object = match value {
    @cjson.Json::Object(fields) => fields
    @cjson.Json::Null => return
    _ => raise Syntax("expected an object for Struct")
  }
  let field = match message_field_by_name(message, "fields") {
    Some(field) => field
    None => return
  }
  let map = message.mutable(field).map()
  for pair in object {
    let nested = map.mutable(@reflect.String(pair.0))
    value_from_json(nested.message(), pair.1, opts, depth + 1)
  }
}

///|
fn list_value_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let items = match value {
    @cjson.Json::Array(items) => items
    @cjson.Json::Null => return
    _ => raise Syntax("expected an array for ListValue")
  }
  let field = match message_field_by_name(message, "values") {
    Some(field) => field
    None => return
  }
  let list = message.mutable(field).list()
  for item in items {
    let element = list.append_mutable()
    value_from_json(element.message(), item, opts, depth + 1)
  }
}

///|
fn value_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if depth > opts.recursion_limit {
    raise Recursion(opts.recursion_limit)
  }
  match value {
    @cjson.Json::Null =>
      match message_field_by_name(message, "null_value") {
        Some(field) => message.set(field, @reflect.Enum(0))
        None => ()
      }
    @cjson.Json::True =>
      match message_field_by_name(message, "bool_value") {
        Some(field) => message.set(field, @reflect.Bool(true))
        None => ()
      }
    @cjson.Json::False =>
      match message_field_by_name(message, "bool_value") {
        Some(field) => message.set(field, @reflect.Bool(false))
        None => ()
      }
    @cjson.Json::Number(number, ..) =>
      match message_field_by_name(message, "number_value") {
        Some(field) => message.set(field, @reflect.Double(number))
        None => ()
      }
    @cjson.Json::String(text) =>
      match message_field_by_name(message, "string_value") {
        Some(field) => message.set(field, @reflect.String(text))
        None => ()
      }
    @cjson.Json::Array(_) =>
      match message_field_by_name(message, "list_value") {
        Some(field) =>
          list_value_from_json(
            message.mutable(field).message(),
            value,
            opts,
            depth + 1,
          )
        None => ()
      }
    @cjson.Json::Object(_) =>
      match message_field_by_name(message, "struct_value") {
        Some(field) =>
          struct_from_json(
            message.mutable(field).message(),
            value,
            opts,
            depth + 1,
          )
        None => ()
      }
  }
}

///|
fn field_from_json(
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if value is @cjson.Json::Null {
    message.clear(field)
    return
  }
  if field.is_map {
    let object = match value {
      @cjson.Json::Object(fields) => fields
      _ => raise Syntax("expected an object for " + field.name)
    }
    let map = message.mutable(field).map()
    let value_field = match field.map_value_field {
      Some(item) => item
      None => return
    }
    for pair in object {
      let key = match string_to_map_key(pair.0, field) {
        Some(key) => key
        None => raise BadValue(field.name)
      }
      map.set(key, json_to_value(value_field, pair.1, opts, depth))
    }
    return
  }
  if field.is_list() {
    let items = match value {
      @cjson.Json::Array(items) => items
      _ => raise Syntax("expected an array for " + field.name)
    }
    let list = message.mutable(field).list()
    for item in items {
      list.append(json_to_value(field, item, opts, depth))
    }
    return
  }
  if field.kind.is_message() {
    let target = message.mutable(field).message()
    message_from_json(target, value, opts, depth + 1)
    return
  }
  message.set(field, json_to_value(field, value, opts, depth))
}

///|
fn json_to_value(
  field : @reflect.FieldDescriptor,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> @reflect.Value raise Refused {
  let _ = opts
  let _ = depth
  match field.kind {
    @reflect.Bool =>
      match value {
        @cjson.Json::True => @reflect.Bool(true)
        @cjson.Json::False => @reflect.Bool(false)
        _ => raise BadValue(field.name)
      }
    @reflect.String =>
      match value {
        @cjson.Json::String(text) => @reflect.String(text)
        _ => raise BadValue(field.name)
      }
    @reflect.Bytes =>
      match value {
        @cjson.Json::String(text) =>
          @reflect.Bytes(
            @base64.decode(text) catch {
              _ => raise BadBase64(field.name)
            },
          )
        _ => raise BadValue(field.name)
      }
    @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 =>
      @reflect.Int32(parse_int64(numeric_text(value, field.name)).to_int())
    @reflect.Uint32 | @reflect.Fixed32 =>
      @reflect.Uint32(parse_uint64(numeric_text(value, field.name)).to_uint())
    @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>
      @reflect.Int64(parse_int64(numeric_text(value, field.name)))
    @reflect.Uint64 | @reflect.Fixed64 =>
      @reflect.Uint64(parse_uint64(numeric_text(value, field.name)))
    @reflect.Float =>
      @reflect.Float(@float.Float::from_double(float_value(value, field.name)))
    @reflect.Double => @reflect.Double(float_value(value, field.name))
    @reflect.Enum => enum_from_json(field, value)
    @reflect.Message | @reflect.Group => {
      let nested = @reflect.new_field_value(field)
      message_from_json(nested.message(), value, opts, depth + 1)
      nested
    }
  }
}

///|
fn numeric_text(value : @cjson.Json, name : String) -> String raise Refused {
  match value {
    @cjson.Json::Number(number, ..) => number.to_string()
    @cjson.Json::String(text) => text
    _ => raise BadValue(name)
  }
}

///|
fn parse_int64(text : StringView) -> Int64 raise Refused {
  let mut i = 0
  let negative = text.length() > 0 && text[0] == '-'
  if negative {
    i = 1
  }
  if text.length() == i {
    raise BadValue("number")
  }
  let mut value = 0L
  while i < text.length() {
    let c = text[i]
    if c < '0' || c > '9' {
      raise BadValue("number")
    }
    value = value * 10L + (c.to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn parse_uint64(text : StringView) -> UInt64 raise Refused {
  let mut i = 0
  let mut value = 0UL
  while i < text.length() {
    let c = text[i]
    if c < '0' || c > '9' {
      raise BadValue("number")
    }
    value = value * 10UL + (c.to_int() - '0'.to_int()).to_uint64()
    i = i + 1
  }
  value
}

///|
fn float_value(value : @cjson.Json, name : String) -> Double raise Refused {
  match value {
    @cjson.Json::Number(number, ..) => number
    @cjson.Json::String("NaN") => @double.not_a_number
    @cjson.Json::String("Infinity") => @double.infinity
    @cjson.Json::String("-Infinity") => @double.neg_infinity
    @cjson.Json::String(text) =>
      match
        (@cjson.parse(text, preserve_number_repr=true) catch {
          _ => raise BadValue(name)
        }) {
        @cjson.Json::Number(number, ..) => number
        _ => raise BadValue(name)
      }
    _ => raise BadValue(name)
  }
}

///|
fn enum_from_json(
  field : @reflect.FieldDescriptor,
  value : @cjson.Json,
) -> @reflect.Value raise Refused {
  match value {
    @cjson.Json::Number(number, ..) => @reflect.Enum(number.to_int())
    @cjson.Json::String(name) =>
      match field.enum_type {
        Some(enum_name) =>
          match @reflect.global_files.find_enum_by_name(enum_name) {
            Some(desc) =>
              match desc.value_by_name(name) {
                Some(item) => @reflect.Enum(item.number)
                None => raise BadValue(field.name)
              }
            None => raise BadValue(field.name)
          }
        None => raise BadValue(field.name)
      }
    _ => raise BadValue(field.name)
  }
}

///|
fn string_to_map_key(
  text : String,
  field : @reflect.FieldDescriptor,
) -> @reflect.MapKey? raise Refused {
  match field.map_key_field {
    Some(key) =>
      match key.kind {
        @reflect.Bool =>
          if text == "true" {
            Some(@reflect.Bool(true))
          } else if text == "false" {
            Some(@reflect.Bool(false))
          } else {
            None
          }
        @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 =>
          Some(@reflect.Int32(parse_int64(text).to_int()))
        @reflect.Uint32 | @reflect.Fixed32 =>
          Some(@reflect.Uint32(parse_uint64(text).to_uint()))
        @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>
          Some(@reflect.Int64(parse_int64(text)))
        @reflect.Uint64 | @reflect.Fixed64 =>
          Some(@reflect.Uint64(parse_uint64(text)))
        @reflect.String => Some(@reflect.String(text))
        _ => None
      }
    None => None
  }
}

///|
fn wrapper_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
) -> Unit raise Refused {
  match message.descriptor().field_by_number(1) {
    Some(field) => message.set(field, json_to_value(field, value, opts, 1))
    None => ()
  }
}

///|
fn set_number_field(
  message : &@reflect.Message,
  number : Int32,
  value : @reflect.Value,
) -> Unit {
  match message.descriptor().field_by_number(number) {
    Some(field) => message.set(field, value)
    None => ()
  }
}

///|
fn timestamp_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
) -> Unit raise Refused {
  let text = match value {
    @cjson.Json::String(text) => text
    _ => raise Syntax("expected a timestamp string")
  }
  let (seconds, nanos) = parse_timestamp(text)
  set_number_field(message, 1, @reflect.Int64(seconds))
  if nanos != 0 {
    set_number_field(message, 2, @reflect.Int32(nanos))
  }
}

///|
fn duration_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
) -> Unit raise Refused {
  let text = match value {
    @cjson.Json::String(text) => text
    _ => raise Syntax("expected a duration string")
  }
  let (seconds, nanos) = parse_duration(text)
  set_number_field(message, 1, @reflect.Int64(seconds))
  if nanos != 0 {
    set_number_field(message, 2, @reflect.Int32(nanos))
  }
}

///|
fn field_mask_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
) -> Unit raise Refused {
  let text = match value {
    @cjson.Json::String(text) => text
    _ => raise Syntax("expected a field mask string")
  }
  match message.descriptor().field_by_number(1) {
    Some(field) => {
      let list = message.mutable(field).list()
      if text.length() > 0 {
        for part in text.split(",") {
          list.append(@reflect.String(part.to_owned()))
        }
      }
    }
    None => ()
  }
}

///|
fn any_from_json(
  message : &@reflect.Message,
  value : @cjson.Json,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let object = match value {
    @cjson.Json::Object(fields) => fields
    _ => raise Syntax("expected an object for Any")
  }
  let type_url = match object.get("@type") {
    Some(@cjson.Json::String(text)) => text
    _ => raise BadValue("@type")
  }
  let name = type_url_after_slash(type_url)
  let message_type = match @reflect.global_types.find_message_by_name(name) {
    Some(found) => found
    None => raise NoType(name)
  }
  let nested = message_type.new_message()
  let rest : Map[String, @cjson.Json] = Map([])
  for pair in object {
    if pair.0 != "@type" {
      rest.set(pair.0, pair.1)
    }
  }
  message_from_json(nested, @cjson.Json::object(rest), opts, depth + 1)
  let body = @proto.encode(nested) catch { _ => raise BadValue("Any.value") }
  set_number_field(message, 1, @reflect.String(type_url))
  set_number_field(message, 2, @reflect.Bytes(body))
}

// -- time formatting --------------------------------------------------------

///|
/// Days since 1970-01-01 to a civil date, after Howard Hinnant's algorithm.
fn civil_from_days(days : Int64) -> (Int64, Int32, Int32) {
  let z = days + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  let year = if m <= 2L { y + 1L } else { y }
  (year, m.to_int(), d.to_int())
}

///|
fn pad2(value : Int32) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn pad9(value : Int32) -> String {
  let text = value.to_string()
  let mut result = ""
  for _ in 0..<(9 - text.length()) {
    result = result + "0"
  }
  result + text
}

///|
fn format_timestamp(seconds : Int64, nanos : Int32) -> String {
  let days = if seconds >= 0L {
    seconds / 86400L
  } else {
    (seconds - 86399L) / 86400L
  }
  let rem = seconds - days * 86400L
  let (year, month, day) = civil_from_days(days)
  let hour = (rem / 3600L).to_int()
  let minute = (rem % 3600L / 60L).to_int()
  let second = (rem % 60L).to_int()
  let base = year.to_string() +
    "-" +
    pad2(month) +
    "-" +
    pad2(day) +
    "T" +
    pad2(hour) +
    ":" +
    pad2(minute) +
    ":" +
    pad2(second)
  if nanos == 0 {
    base + "Z"
  } else {
    base + "." + pad9(nanos) + "Z"
  }
}

///|
fn format_duration(seconds : Int64, nanos : Int32) -> String {
  let sign = if seconds < 0L || nanos < 0 { "-" } else { "" }
  let abs_seconds = if seconds < 0L { -seconds } else { seconds }
  let abs_nanos = if nanos < 0 { -nanos } else { nanos }
  if abs_nanos == 0 {
    sign + abs_seconds.to_string() + "s"
  } else {
    sign + abs_seconds.to_string() + "." + pad9(abs_nanos) + "s"
  }
}

///|
fn parse_timestamp(text : String) -> (Int64, Int32) raise Refused {
  // YYYY-MM-DDTHH:MM:SS[.fffffffff]Z
  if text.length() < 20 {
    raise Syntax("bad timestamp")
  }
  let year = parse_int64(text[0:4])
  let month = parse_int64(text[5:7]).to_int()
  let day = parse_int64(text[8:10]).to_int()
  let hour = parse_int64(text[11:13]).to_int()
  let minute = parse_int64(text[14:16]).to_int()
  let second = parse_int64(text[17:19]).to_int()
  let mut nanos = 0
  if text.length() > 20 && text[19] == '.' {
    let mut i = 20
    let mut digits = 0
    while i < text.length() && text[i] != 'Z' && digits < 9 {
      nanos = nanos * 10 + (text[i].to_int() - '0'.to_int())
      digits = digits + 1
      i = i + 1
    }
    while digits < 9 {
      nanos = nanos * 10
      digits = digits + 1
    }
  }
  let days = days_from_civil(year, month, day)
  let seconds = days * 86400L + (hour * 3600 + minute * 60 + second).to_int64()
  (seconds, nanos)
}

///|
fn parse_duration(text : String) -> (Int64, Int32) raise Refused {
  if text.length() < 2 {
    raise Syntax("bad duration")
  }
  let negative = text[0] == '-'
  let body = if negative { text[1:].to_owned() } else { text }
  if body[body.length() - 1] != 's' {
    raise Syntax("bad duration")
  }
  let number = body[:body.length() - 1].to_owned()
  let mut seconds = 0L
  let mut nanos = 0
  let mut i = 0
  while i < number.length() && number[i] != '.' {
    seconds = seconds * 10L + (number[i].to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  if i < number.length() && number[i] == '.' {
    i = i + 1
    let mut digits = 0
    while i < number.length() && digits < 9 {
      nanos = nanos * 10 + (number[i].to_int() - '0'.to_int())
      digits = digits + 1
      i = i + 1
    }
    while digits < 9 {
      nanos = nanos * 10
      digits = digits + 1
    }
  }
  if negative {
    (-seconds, -nanos)
  } else {
    (seconds, nanos)
  }
}

///|
fn days_from_civil(year : Int64, month : Int32, day : Int32) -> Int64 {
  let y = if month <= 2 { year - 1L } else { year }
  let era = if y >= 0L { y / 400L } else { (y - 399L) / 400L }
  let yoe = y - era * 400L
  let m = month.to_int64()
  let d = day.to_int64()
  let mp = if m > 2L { m - 3L } else { m + 9L }
  let doy = (153L * mp + 2L) / 5L + d - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}
