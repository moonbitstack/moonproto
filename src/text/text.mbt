// The text format encoder and decoder.

///|
pub(all) struct MarshalOptions {
  multiline : Bool
  indent : String
  emit_ascii : Bool
  allow_partial : Bool
}

///|
pub let marshal_options : MarshalOptions = {
  multiline: true,
  indent: "  ",
  emit_ascii: false,
  allow_partial: false,
}

///|
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
/// A text-format refusal.
pub(all) suberror Refused {
  Syntax(String, Int32)
  UnknownField(String)
  BadValue(String)
  NoType(String)
  Required(String)
  Recursion(Int32)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Syntax(message, at) =>
      logger.write_string("syntax at " + at.to_string() + ": " + message)
    UnknownField(name) => logger.write_string("unknown field " + name)
    BadValue(name) => logger.write_string("bad value for " + name)
    NoType(name) => logger.write_string("no message type " + name)
    Required(name) =>
      logger.write_string("required field " + name + " is unset")
    Recursion(limit) =>
      logger.write_string("recursion limit " + limit.to_string())
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
fn char_at(text : String, index : Int32) -> Char {
  text[index].to_int().to_char().unwrap_or('?')
}

///|
/// The text of `message`.
pub fn[M : @reflect.Message] encode(
  message : M,
  marshal_options~ : MarshalOptions = marshal_options,
) -> String raise Refused {
  if !marshal_options.allow_partial {
    match @reflect.missing_required(message as &@reflect.Message) {
      Some(path) => raise Required(path)
      None => ()
    }
  }
  let buf = Buffer()
  encode_message(buf, message as &@reflect.Message, marshal_options, 0)
  @utf8.decode(buf.to_bytes()) catch {
    _ => raise Syntax("utf8", 0)
  }
}

///|
/// Read text into `message`, replacing its contents.
pub fn[M : @reflect.Message] decode(
  text : StringView,
  message : M,
  unmarshal_options~ : UnmarshalOptions = unmarshal_options,
) -> Unit raise Refused {
  let desc = message.descriptor()
  for field in desc.fields {
    message.clear(field)
  }
  let parser = Parser::new(text.to_owned())
  message_from_text(message as &@reflect.Message, parser, unmarshal_options, 0)
  parser.finish()
  if !unmarshal_options.allow_partial {
    match @reflect.missing_required(message as &@reflect.Message) {
      Some(path) => raise Required(path)
      None => ()
    }
  }
}

// -- encoding ---------------------------------------------------------------

///|
fn encode_message(
  buf : Buffer,
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if depth > 100 {
    raise Recursion(100)
  }
  // An Any prints as the type's own text inside a bracketed type URL, so the
  // reader sees the payload rather than an opaque byte string.
  if message.descriptor().full_name == "google.protobuf.Any" &&
    encode_any_text(buf, message, opts, depth) {
    return
  }
  for field in message.descriptor().fields {
    if field.is_map {
      if message.has(field) {
        let entries : Array[(@reflect.MapKey, @reflect.Value)] = []
        message
        .get(field)
        .map()
        .range(fn(key, value) {
          entries.push((key, value))
          true
        })
        match (field.map_key_field, field.map_value_field) {
          (Some(key_field), Some(value_field)) =>
            for entry in entries {
              write_indent(buf, opts, depth)
              buf.write_string_utf8(field.text_name)
              buf.write_string_utf8(" {")
              buf.write_string_utf8("\n")
              write_indent(buf, opts, depth + 1)
              buf.write_string_utf8(key_field.text_name + ": ")
              scalar_text(buf, key_field, entry.0.value(), opts)
              buf.write_string_utf8("\n")
              write_indent(buf, opts, depth + 1)
              buf.write_string_utf8(value_field.text_name + ": ")
              value_text(buf, value_field, entry.1, opts, depth + 1)
              buf.write_string_utf8("\n")
              write_indent(buf, opts, depth)
              buf.write_string_utf8("}\n")
            }
          _ => ()
        }
      }
    } else if field.is_list() {
      if message.has(field) {
        let list = message.get(field).list()
        for i in 0..<list.length() {
          write_indent(buf, opts, depth)
          buf.write_string_utf8(field.text_name + ": ")
          value_text(buf, field, list.get(i), opts, depth)
          buf.write_string_utf8("\n")
        }
      }
    } else if message.has(field) {
      write_indent(buf, opts, depth)
      match field.kind {
        @reflect.Message | @reflect.Group => {
          buf.write_string_utf8(field.text_name + " {\n")
          encode_message(buf, message.get(field).message(), opts, depth + 1)
          write_indent(buf, opts, depth)
          buf.write_string_utf8("}\n")
        }
        _ => {
          buf.write_string_utf8(field.text_name + ": ")
          scalar_text(buf, field, message.get(field), opts)
          buf.write_string_utf8("\n")
        }
      }
    }
  }
  // An extension is named by its full name in brackets.
  let extensions : Array[@reflect.FieldDescriptor] = []
  message.range_extensions(fn(field, _value) {
    extensions.push(field)
    true
  })
  for field in extensions {
    write_extension_text(buf, message, field, opts, depth)
  }
}

///|
fn write_extension_text(
  buf : Buffer,
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let label = "[" + field.full_name + "]"
  if field.is_list() {
    let list = message.get(field).list()
    for i in 0..<list.length() {
      write_indent(buf, opts, depth)
      buf.write_string_utf8(label + ": ")
      value_text(buf, field, list.get(i), opts, depth)
      buf.write_string_utf8("\n")
    }
  } else {
    write_indent(buf, opts, depth)
    match field.kind {
      @reflect.Message | @reflect.Group => {
        buf.write_string_utf8(label + " {\n")
        encode_message(buf, message.get(field).message(), opts, depth + 1)
        write_indent(buf, opts, depth)
        buf.write_string_utf8("}\n")
      }
      _ => {
        buf.write_string_utf8(label + ": ")
        scalar_text(buf, field, message.get(field), opts)
        buf.write_string_utf8("\n")
      }
    }
  }
}

///|
/// The last path segment of a type URL, which is the type's full name.
fn type_url_name(url : String) -> String {
  let mut start = 0
  let mut i = 0
  while i < url.length() {
    if char_at(url, i) == '/' {
      start = i + 1
    }
    i = i + 1
  }
  url[start:url.length()].to_owned()
}

///|
/// Write the expanded form of an `Any`, returning false when there is nothing
/// to expand (no type URL, or a type that is not registered).
fn encode_any_text(
  buf : Buffer,
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> Bool raise Refused {
  let desc = message.descriptor()
  let type_field = match desc.field_by_number(1) {
    Some(field) => field
    None => return false
  }
  let value_field = match desc.field_by_number(2) {
    Some(field) => field
    None => return false
  }
  if !message.has(type_field) {
    return false
  }
  let url = message.get(type_field).string()
  let name = type_url_name(url)
  let message_type = match @reflect.global_types.find_message_by_name(name) {
    Some(found) => found
    None => return false
  }
  let nested = message_type.new_message()
  if message.has(value_field) {
    @proto.decode(message.get(value_field).bytes(), nested) catch {
      _ => return false
    }
  }
  write_indent(buf, opts, depth)
  buf.write_string_utf8("[" + url + "] {\n")
  encode_message(buf, nested, opts, depth + 1)
  write_indent(buf, opts, depth)
  buf.write_string_utf8("}\n")
  true
}

///|
fn write_indent(buf : Buffer, opts : MarshalOptions, depth : Int32) -> Unit {
  if opts.multiline {
    for _ in 0..<depth {
      buf.write_string_utf8(opts.indent)
    }
  }
}

///|
fn value_text(
  buf : Buffer,
  field : @reflect.FieldDescriptor,
  value : @reflect.Value,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  match field.kind {
    @reflect.Message | @reflect.Group =>
      encode_message(buf, value.message(), opts, depth)
    _ => scalar_text(buf, field, value, opts)
  }
}

///|
fn scalar_text(
  buf : Buffer,
  field : @reflect.FieldDescriptor,
  value : @reflect.Value,
  opts : MarshalOptions,
) -> Unit {
  match field.kind {
    @reflect.Bool =>
      buf.write_string_utf8(if value.bool() { "true" } else { "false" })
    @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 =>
      buf.write_string_utf8(value.int().to_string())
    @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>
      buf.write_string_utf8(value.int().to_string())
    @reflect.Uint32 | @reflect.Fixed32 =>
      buf.write_string_utf8(value.uint().to_string())
    @reflect.Uint64 | @reflect.Fixed64 =>
      buf.write_string_utf8(value.uint().to_string())
    @reflect.Float | @reflect.Double => {
      let number = value.float()
      if number.is_nan() {
        buf.write_string_utf8("nan")
      } else if number.is_inf() {
        buf.write_string_utf8(if number > 0.0 { "inf" } else { "-inf" })
      } else {
        buf.write_string_utf8(number.to_string())
      }
    }
    @reflect.String => write_quoted(buf, value.string(), opts.emit_ascii)
    @reflect.Bytes => write_bytes_quoted(buf, value.bytes(), opts.emit_ascii)
    @reflect.Enum => {
      let number = value.enum_number()
      let mut written = false
      match field.enum_type {
        Some(name) =>
          match @reflect.global_files.find_enum_by_name(name) {
            Some(desc) =>
              match desc.value_by_number(number) {
                Some(item) => {
                  buf.write_string_utf8(item.name)
                  written = true
                }
                None => ()
              }
            None => ()
          }
        None => ()
      }
      if !written {
        buf.write_string_utf8(number.to_string())
      }
    }
    @reflect.Message | @reflect.Group => ()
  }
}

///|
fn write_quoted(buf : Buffer, text : String, ascii : Bool) -> Unit {
  buf.write_string_utf8("\"")
  for i in 0..<text.length() {
    let ch = char_at(text, i)
    write_escaped(buf, ch, ascii)
  }
  buf.write_string_utf8("\"")
}

///|
fn write_bytes_quoted(buf : Buffer, bytes : Bytes, ascii : Bool) -> Unit {
  buf.write_string_utf8("\"")
  for i in 0..<bytes.length() {
    let byte = bytes[i]
    if byte.to_int() >= 0x20 &&
      byte.to_int() < 0x7F &&
      byte.to_int() != 0x22 &&
      byte.to_int() != 0x5C {
      buf.write_byte(byte)
    } else {
      buf.write_string_utf8("\\x")
      buf.write_string_utf8(hex_digit(byte.to_int() >> 4))
      buf.write_string_utf8(hex_digit(byte.to_int() & 0xF))
    }
  }
  buf.write_string_utf8("\"")
  let _ = ascii
}

///|
fn hex_digit(value : Int32) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    _ => "f"
  }
}

///|
fn write_escaped(buf : Buffer, ch : Char, ascii : Bool) -> Unit {
  let code = ch.to_int()
  if ch == '"' {
    buf.write_string_utf8("\\\"")
  } else if ch == '\\' {
    buf.write_string_utf8("\\\\")
  } else if ch == '\n' {
    buf.write_string_utf8("\\n")
  } else if ch == '\r' {
    buf.write_string_utf8("\\r")
  } else if ch == '\t' {
    buf.write_string_utf8("\\t")
  } else if code < 0x20 {
    buf.write_string_utf8("\\x")
    buf.write_string_utf8(hex_digit((code >> 4) & 0xF))
    buf.write_string_utf8(hex_digit(code & 0xF))
  } else if ascii && code > 0x7F {
    // Escape the UTF-8 bytes so the output is ASCII only.
    let bytes = @utf8.encode(ch.to_string())
    for i in 0..<bytes.length() {
      buf.write_string_utf8("\\x")
      buf.write_string_utf8(hex_digit(bytes[i].to_int() >> 4))
      buf.write_string_utf8(hex_digit(bytes[i].to_int() & 0xF))
    }
  } else {
    buf.write_string_utf8(ch.to_string())
  }
}

// -- parsing ----------------------------------------------------------------

///|
priv struct Parser {
  text : String
  mut pos : Int32
}

///|
fn Parser::new(text : String) -> Parser {
  { text, pos: 0, }
}

///|
fn Parser::finish(self : Parser) -> Unit raise Refused {
  self.skip()
  if self.pos < self.text.length() {
    raise Syntax("trailing input", self.pos)
  }
}

///|
fn Parser::skip(self : Parser) -> Unit {
  while self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      self.pos = self.pos + 1
    } else if ch == '#' {
      while self.pos < self.text.length() &&
            char_at(self.text, self.pos) != '\n' {
        self.pos = self.pos + 1
      }
    } else {
      break
    }
  }
}

///|
fn Parser::peek(self : Parser) -> Char? {
  self.skip()
  if self.pos < self.text.length() {
    Some(char_at(self.text, self.pos))
  } else {
    None
  }
}

///|
fn Parser::eof(self : Parser) -> Bool {
  self.skip()
  self.pos >= self.text.length()
}

///|
fn Parser::expect(self : Parser, ch : Char) -> Unit raise Refused {
  self.skip()
  if self.pos >= self.text.length() || char_at(self.text, self.pos) != ch {
    raise Syntax("expected " + ch.to_string(), self.pos)
  }
  self.pos = self.pos + 1
}

///|
/// A bracketed name: a type URL may contain `/`, an extension name may contain
/// dots, so it runs to the closing bracket.
fn Parser::read_type_url(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  while self.pos < self.text.length() && char_at(self.text, self.pos) != ']' {
    self.pos = self.pos + 1
  }
  if self.pos >= self.text.length() {
    raise Syntax("unterminated name", start)
  }
  let name = self.text[start:self.pos].to_owned()
  if name.length() == 0 {
    raise Syntax("empty name", start)
  }
  name
}

///|
fn is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

///|
fn is_ident_char(ch : Char) -> Bool {
  is_ident_start(ch) || (ch >= '0' && ch <= '9') || ch == '.'
}

///|
fn Parser::read_ident(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  while self.pos < self.text.length() &&
        is_ident_char(char_at(self.text, self.pos)) {
    self.pos = self.pos + 1
  }
  if self.pos == start {
    raise Syntax("expected a name", self.pos)
  }
  self.text[start:self.pos].to_owned()
}

///|
fn Parser::read_number(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  while self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if (ch >= '0' && ch <= '9') ||
      ch == '+' ||
      ch == '-' ||
      ch == '.' ||
      ch == 'e' ||
      ch == 'E' ||
      ch == 'x' ||
      ch == 'X' ||
      (ch >= 'a' && ch <= 'f') ||
      (ch >= 'A' && ch <= 'F') {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  if self.pos == start {
    raise Syntax("expected a number", self.pos)
  }
  self.text[start:self.pos].to_owned()
}

///|
fn Parser::read_string(self : Parser) -> Bytes raise Refused {
  self.skip()
  let quote = if self.pos < self.text.length() {
    char_at(self.text, self.pos)
  } else {
    raise Syntax("expected a string", self.pos)
  }
  if quote != '"' && quote != '\'' {
    raise Syntax("expected a string", self.pos)
  }
  self.pos = self.pos + 1
  let out = Buffer()
  while true {
    if self.pos >= self.text.length() {
      raise Syntax("unterminated string", self.pos)
    }
    let ch = char_at(self.text, self.pos)
    if ch == quote {
      self.pos = self.pos + 1
      return out.to_bytes()
    }
    if ch == '\\' {
      self.pos = self.pos + 1
      if self.pos >= self.text.length() {
        raise Syntax("unterminated escape", self.pos)
      }
      let esc = char_at(self.text, self.pos)
      self.pos = self.pos + 1
      if esc == 'n' {
        out.write_byte(0x0A)
      } else if esc == 'r' {
        out.write_byte(0x0D)
      } else if esc == 't' {
        out.write_byte(0x09)
      } else if esc == '\\' || esc == '"' || esc == '\'' {
        out.write_byte(esc.to_int().to_byte())
      } else if esc == 'x' || esc == 'X' {
        let high = self.read_hex_digit()
        let low = self.read_hex_digit()
        out.write_byte(((high << 4) | low).to_byte())
      } else if esc >= '0' && esc <= '7' {
        let mut value = esc.to_int() - '0'.to_int()
        let mut count = 1
        while count < 3 &&
              self.pos < self.text.length() &&
              char_at(self.text, self.pos) >= '0' &&
              char_at(self.text, self.pos) <= '7' {
          value = value * 8 +
            (char_at(self.text, self.pos).to_int() - '0'.to_int())
          self.pos = self.pos + 1
          count = count + 1
        }
        out.write_byte(value.to_byte())
      } else {
        raise Syntax("unknown escape", self.pos)
      }
    } else {
      let bytes = @utf8.encode(ch.to_string())
      for i in 0..<bytes.length() {
        out.write_byte(bytes[i])
      }
      self.pos = self.pos + 1
    }
  }
  out.to_bytes()
}

///|
fn Parser::read_hex_digit(self : Parser) -> Int32 raise Refused {
  if self.pos >= self.text.length() {
    raise Syntax("expected a hex digit", self.pos)
  }
  let ch = char_at(self.text, self.pos)
  self.pos = self.pos + 1
  if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 'a'.to_int() + 10
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 'A'.to_int() + 10
  } else {
    raise Syntax("expected a hex digit", self.pos)
  }
}

///|
fn message_from_text(
  message : &@reflect.Message,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if depth > opts.recursion_limit {
    raise Recursion(opts.recursion_limit)
  }
  while true {
    parser.skip()
    if parser.eof() || parser.peek() == Some('}') || parser.peek() == Some('>') {
      return
    }
    let mut qualified : String? = None
    let name = if parser.peek() == Some('[') {
      parser.expect('[')
      let key = parser.read_type_url()
      parser.expect(']')
      qualified = Some(key)
      key
    } else {
      parser.read_ident()
    }
    if parser.peek() == Some(':') {
      parser.expect(':')
    }
    match qualified {
      Some(key) => {
        if message.descriptor().full_name == "google.protobuf.Any" &&
          key.contains("/") {
          parse_any_text(message, key, parser, opts, depth)
          continue
        }
        match @reflect.global_types.find_extension_by_name(key) {
          Some(extension) => {
            let field = extension.descriptor()
            parse_field(message, field, parser, opts, depth)
            continue
          }
          None => if !opts.discard_unknown { raise UnknownField(key) }
        }
      }
      None => ()
    }
    match message.descriptor().field_by_json_name(name) {
      Some(field) => parse_field(message, field, parser, opts, depth)
      None =>
        match message.descriptor().field_by_name(name) {
          Some(field) => parse_field(message, field, parser, opts, depth)
          None =>
            if !opts.discard_unknown {
              raise UnknownField(name)
            } else {
              skip_value(parser)
            }
        }
    }
  }
}

///|
/// Read the expanded body of an `Any`: the payload becomes the type's own text,
/// and the type URL is restored from the bracket.
fn parse_any_text(
  message : &@reflect.Message,
  url : String,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let desc = message.descriptor()
  let type_field = match desc.field_by_number(1) {
    Some(field) => field
    None => raise Syntax("Any has no type_url", parser.pos)
  }
  let value_field = match desc.field_by_number(2) {
    Some(field) => field
    None => raise Syntax("Any has no value", parser.pos)
  }
  let name = type_url_name(url)
  let message_type = match @reflect.global_types.find_message_by_name(name) {
    Some(found) => found
    None => raise NoType(name)
  }
  let nested = message_type.new_message()
  parse_message_value(nested, parser, opts, depth + 1)
  let body = @proto.encode(nested) catch { _ => raise BadValue("Any.value") }
  message.set(type_field, @reflect.String(url))
  message.set(value_field, @reflect.Bytes(body))
}

///|
fn parse_field(
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if field.is_map {
    let entry = message.mutable(field).map()
    let key_field = match field.map_key_field {
      Some(item) => item
      None => return
    }
    let value_field = match field.map_value_field {
      Some(item) => item
      None => return
    }
    parser.expect('{')
    let mut key : @reflect.Value = @reflect.default_for(key_field)
    let mut value : @reflect.Value = @reflect.new_field_value(value_field)
    while true {
      parser.skip()
      if parser.peek() == Some('}') {
        parser.expect('}')
        break
      }
      let name = parser.read_ident()
      if parser.peek() == Some(':') {
        parser.expect(':')
      }
      if name == key_field.text_name {
        key = parse_scalar(key_field, parser, opts, depth)
      } else if name == value_field.text_name {
        value = parse_value(value_field, parser, opts, depth)
      } else {
        skip_value(parser)
      }
    }
    match key.map_key() {
      Some(map_key) => entry.set(map_key, value)
      None => ()
    }
    return
  }
  if field.is_list() {
    let value = parse_value(field, parser, opts, depth)
    message.mutable(field).list().append(value)
    return
  }
  if field.kind.is_message() {
    let target = message.mutable(field).message()
    parse_message_value(target, parser, opts, depth)
    return
  }
  message.set(field, parse_scalar(field, parser, opts, depth))
}

///|
fn parse_value(
  field : @reflect.FieldDescriptor,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> @reflect.Value raise Refused {
  if field.kind.is_message() {
    let nested = @reflect.new_field_value(field)
    parse_message_value(nested.message(), parser, opts, depth)
    nested
  } else {
    parse_scalar(field, parser, opts, depth)
  }
}

///|
fn parse_message_value(
  message : &@reflect.Message,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  parser.skip()
  match parser.peek() {
    Some('{') => {
      parser.expect('{')
      message_from_text(message, parser, opts, depth + 1)
      parser.expect('}')
    }
    Some('<') => {
      parser.expect('<')
      message_from_text(message, parser, opts, depth + 1)
      parser.expect('>')
    }
    _ => raise Syntax("expected a message body", parser.pos)
  }
}

///|
fn parse_scalar(
  field : @reflect.FieldDescriptor,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> @reflect.Value raise Refused {
  match field.kind {
    @reflect.Bool => {
      let word = parser.read_ident()
      if word == "true" || word == "t" || word == "1" {
        @reflect.Bool(true)
      } else if word == "false" || word == "f" || word == "0" {
        @reflect.Bool(false)
      } else {
        raise BadValue(field.name)
      }
    }
    @reflect.String => {
      let bytes = parser.read_string()
      @reflect.String(
        @utf8.decode(bytes) catch {
          _ => raise BadValue(field.name)
        },
      )
    }
    @reflect.Bytes => @reflect.Bytes(parser.read_string())
    @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 =>
      @reflect.Int32(parse_int_text(parser.read_number()).to_int())
    @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>
      @reflect.Int64(parse_int_text(parser.read_number()))
    @reflect.Uint32 | @reflect.Fixed32 =>
      @reflect.Uint32(
        parse_int_text(parser.read_number()).to_int().reinterpret_as_uint(),
      )
    @reflect.Uint64 | @reflect.Fixed64 =>
      @reflect.Uint64(
        parse_int_text(parser.read_number()).reinterpret_as_uint64(),
      )
    @reflect.Float =>
      @reflect.Float(@float.Float::from_double(parse_float_text(parser)))
    @reflect.Double => @reflect.Double(parse_float_text(parser))
    @reflect.Enum => {
      let token = parser.read_ident()
      let mut value = None
      match field.enum_type {
        Some(name) =>
          match @reflect.global_files.find_enum_by_name(name) {
            Some(desc) =>
              match desc.value_by_name(token) {
                Some(item) => value = Some(item.number)
                None => ()
              }
            None => ()
          }
        None => ()
      }
      match value {
        Some(number) => @reflect.Enum(number)
        None => @reflect.Enum(parse_int_text(token).to_int())
      }
    }
    @reflect.Message | @reflect.Group => {
      let _ = opts
      let _ = depth
      raise BadValue(field.name)
    }
  }
}

///|
fn parse_float_text(parser : Parser) -> Double raise Refused {
  let token = parser.read_number_or_word()
  if token == "inf" || token == "infinity" {
    @double.infinity
  } else if token == "-inf" || token == "-infinity" {
    @double.neg_infinity
  } else if token == "nan" {
    @double.not_a_number
  } else {
    parse_double_text(token)
  }
}

///|
fn Parser::read_number_or_word(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  while self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if is_ident_char(ch) || ch == '+' || ch == '-' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  if self.pos == start {
    raise Syntax("expected a number", self.pos)
  }
  self.text[start:self.pos].to_owned()
}

///|
fn parse_int_text(text : String) -> Int64 raise Refused {
  let mut i = 0
  let negative = text.length() > 0 && text[0] == '-'
  if negative || (text.length() > 0 && text[0] == '+') {
    i = 1
  }
  let mut value = 0L
  if text.length() > i + 1 &&
    char_at(text, i) == '0' &&
    (char_at(text, i + 1) == 'x' || char_at(text, i + 1) == 'X') {
    i = i + 2
    while i < text.length() {
      value = value * 16L + hex_value(char_at(text, i))
      i = i + 1
    }
  } else {
    while i < text.length() {
      let ch = char_at(text, i)
      if ch < '0' || ch > '9' {
        raise BadValue(text)
      }
      value = value * 10L + (ch.to_int() - '0'.to_int()).to_int64()
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
fn hex_value(ch : Char) -> Int64 raise Refused {
  if ch >= '0' && ch <= '9' {
    (ch.to_int() - '0'.to_int()).to_int64()
  } else if ch >= 'a' && ch <= 'f' {
    (ch.to_int() - 'a'.to_int() + 10).to_int64()
  } else if ch >= 'A' && ch <= 'F' {
    (ch.to_int() - 'A'.to_int() + 10).to_int64()
  } else {
    raise BadValue("hex")
  }
}

///|
fn parse_double_text(text : String) -> Double raise Refused {
  let mut i = 0
  let negative = text.length() > 0 && text[0] == '-'
  if negative || (text.length() > 0 && text[0] == '+') {
    i = 1
  }
  let mut value = 0.0
  let mut seen_digit = false
  while i < text.length() && char_at(text, i) >= '0' && char_at(text, i) <= '9' {
    value = value * 10.0 +
      (char_at(text, i).to_int() - '0'.to_int()).to_double()
    seen_digit = true
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
      seen_digit = true
      i = i + 1
    }
  }
  if !seen_digit {
    raise BadValue(text)
  }
  if i < text.length() && (char_at(text, i) == 'e' || char_at(text, i) == 'E') {
    i = i + 1
    let mut exp_negative = false
    if i < text.length() && (char_at(text, i) == '+' || char_at(text, i) == '-') {
      exp_negative = char_at(text, i) == '-'
      i = i + 1
    }
    let mut exponent = 0
    while i < text.length() &&
          char_at(text, i) >= '0' &&
          char_at(text, i) <= '9' {
      exponent = exponent * 10 + (char_at(text, i).to_int() - '0'.to_int())
      i = i + 1
    }
    let mut factor = 1.0
    for _ in 0..<exponent {
      factor = factor * 10.0
    }
    if exp_negative {
      value = value / factor
    } else {
      value = value * factor
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn skip_value(parser : Parser) -> Unit raise Refused {
  parser.skip()
  match parser.peek() {
    Some('{') => {
      parser.expect('{')
      skip_balanced(parser, '}')
    }
    Some('<') => {
      parser.expect('<')
      skip_balanced(parser, '>')
    }
    Some('"') => {
      let _ = parser.read_string()
    }
    Some('\'') => {
      let _ = parser.read_string()
    }
    Some(_) => {
      let _ = parser.read_number_or_word()
    }
    None => ()
  }
}

///|
fn skip_balanced(parser : Parser, close : Char) -> Unit raise Refused {
  while true {
    parser.skip()
    match parser.peek() {
      None => raise Syntax("unterminated value", parser.pos)
      Some(ch) =>
        if ch == close {
          parser.expect(close)
          return
        } else if ch == '{' {
          parser.expect('{')
          skip_balanced(parser, '}')
        } else if ch == '<' {
          parser.expect('<')
          skip_balanced(parser, '>')
        } else if ch == '"' || ch == '\'' {
          let _ = parser.read_string()
        } else {
          let _ = parser.read_number_or_word()
        }
    }
  }
}
