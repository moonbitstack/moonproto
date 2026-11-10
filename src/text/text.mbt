// The text format encoder and decoder.

///|
/// How a message is written in the text format.
pub(all) struct MarshalOptions {
  /// Put one field per line. On by default: the text format is read by people,
  /// and a single line of nested braces is not.
  multiline : Bool
  /// The string one level of nesting is indented with.
  indent : String
  /// Escape every non-ASCII character rather than writing it as itself, for a
  /// reader downstream that only takes ASCII. Off by default.
  emit_ascii : Bool
  /// Skip the check that every required field is set. Off by default.
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
/// How a message is read from the text format.
pub(all) struct UnmarshalOptions {
  /// Accept a message whose required fields are missing. Off by default.
  allow_partial : Bool
  /// Ignore a field the schema does not declare, including a name it reserves,
  /// instead of refusing it.
  discard_unknown : Bool
  /// How deep a nested message may go before the reader refuses.
  recursion_limit : Int32
}

///|
pub let unmarshal_options : UnmarshalOptions = {
  allow_partial: false,
  discard_unknown: false,
  recursion_limit: 10000,
}

///|
/// A text-format refusal. The offset is the position in the input reached when
/// the text stopped making sense.
pub(all) suberror Refused {
  /// The text is not a valid sequence of fields; the payload is the reason and
  /// the offset.
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
    } else if @reflect.is_populated(message, field) {
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
      } else if number == 0.0 &&
        number.reinterpret_as_uint64() == 0x8000_0000_0000_0000UL {
        // A negative zero is not the same value as zero, so it has to keep its
        // sign on the way out or the field stops round-tripping.
        buf.write_string_utf8("-0")
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
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_hex_letter(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

///|
fn is_hex_letter_or_digit(ch : Char) -> Bool {
  is_digit(ch) || is_hex_letter(ch)
}

///|
fn is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

///|
fn is_ident_char(ch : Char) -> Bool {
  is_ident_start(ch) || is_digit(ch)
}

///|
/// The whitespace the text format skips. Vertical tab and form feed are in the
/// list because the grammar treats them as space.
fn is_space_char(ch : Char) -> Bool {
  let code = ch.to_int()
  code == 32 || (code >= 9 && code <= 13)
}

///|
fn Parser::skip(self : Parser) -> Unit {
  while self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if is_space_char(ch) {
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
fn Parser::take(self : Parser, ch : Char) -> Bool {
  self.skip()
  if self.pos < self.text.length() && char_at(self.text, self.pos) == ch {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

///|
fn Parser::finish(self : Parser) -> Unit raise Refused {
  self.skip()
  if self.pos < self.text.length() {
    raise Syntax("trailing input", self.pos)
  }
}

///|
fn Parser::read_ident(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  if self.pos >= self.text.length() ||
    !is_ident_start(char_at(self.text, self.pos)) {
    raise Syntax("expected a name", self.pos)
  }
  self.pos = self.pos + 1
  while self.pos < self.text.length() &&
        is_ident_char(char_at(self.text, self.pos)) {
    self.pos = self.pos + 1
  }
  self.text[start:self.pos].to_owned()
}

///|
/// Read one numeric token: an optional sign, then a decimal or hexadecimal
/// literal, optionally with a fraction, an exponent and a float suffix. The
/// token is returned verbatim because the field's type decides which forms are
/// legal: `012` is a valid integer token and an invalid float token, `0x1` the
/// other way round.
fn Parser::read_number_token(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  if self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if ch == '+' || ch == '-' {
      self.pos = self.pos + 1
    }
  }
  if self.pos + 1 < self.text.length() &&
    char_at(self.text, self.pos) == '0' &&
    (
      char_at(self.text, self.pos + 1) == 'x' ||
      char_at(self.text, self.pos + 1) == 'X'
    ) {
    self.pos = self.pos + 2
    let hex_start = self.pos
    while self.pos < self.text.length() &&
          (
            is_digit(char_at(self.text, self.pos)) ||
            is_hex_letter(char_at(self.text, self.pos))
          ) {
      self.pos = self.pos + 1
    }
    if self.pos == hex_start {
      raise Syntax("expected a digit after 0x", self.pos)
    }
    return self.text[start:self.pos].to_owned()
  }
  let mut whole_digits = 0
  while self.pos < self.text.length() && is_digit(char_at(self.text, self.pos)) {
    self.pos = self.pos + 1
    whole_digits = whole_digits + 1
  }
  let mut fraction_digits = 0
  if self.pos < self.text.length() && char_at(self.text, self.pos) == '.' {
    self.pos = self.pos + 1
    while self.pos < self.text.length() &&
          is_digit(char_at(self.text, self.pos)) {
      self.pos = self.pos + 1
      fraction_digits = fraction_digits + 1
    }
  }
  if whole_digits == 0 && fraction_digits == 0 {
    self.pos = start
    raise Syntax("expected a number", start)
  }
  if self.pos < self.text.length() &&
    (char_at(self.text, self.pos) == 'e' || char_at(self.text, self.pos) == 'E') {
    let mark = self.pos
    self.pos = self.pos + 1
    if self.pos < self.text.length() &&
      (
        char_at(self.text, self.pos) == '+' ||
        char_at(self.text, self.pos) == '-'
      ) {
      self.pos = self.pos + 1
    }
    let exponent_start = self.pos
    while self.pos < self.text.length() &&
          is_digit(char_at(self.text, self.pos)) {
      self.pos = self.pos + 1
    }
    if self.pos == exponent_start {
      // `1e` is not an exponent; leave the `e` for the caller to reject.
      self.pos = mark
    }
  }
  if self.pos < self.text.length() &&
    (char_at(self.text, self.pos) == 'f' || char_at(self.text, self.pos) == 'F') {
    self.pos = self.pos + 1
  }
  self.text[start:self.pos].to_owned()
}

///|
/// Read a bracketed name. Whitespace and comments are dropped, which is how a
/// type URL spread over several lines is read, and a `%` has to introduce two
/// hex digits so a broken percent escape is refused here rather than silently
/// kept.
fn Parser::read_bracket(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  self.expect('[')
  let name = Buffer()
  while true {
    if self.pos >= self.text.length() {
      raise Syntax("unterminated name", start)
    }
    let ch = char_at(self.text, self.pos)
    if ch == ']' {
      self.pos = self.pos + 1
      break
    }
    if is_space_char(ch) {
      self.pos = self.pos + 1
    } else if ch == '#' {
      while self.pos < self.text.length() &&
            char_at(self.text, self.pos) != '\n' {
        self.pos = self.pos + 1
      }
    } else if ch == '%' {
      if self.pos + 2 >= self.text.length() ||
        !is_hex_letter_or_digit(char_at(self.text, self.pos + 1)) ||
        !is_hex_letter_or_digit(char_at(self.text, self.pos + 2)) {
        raise Syntax("bad percent escape", self.pos)
      }
      for offset in 0..<3 {
        name.write_string_utf8(
          char_at(self.text, self.pos + offset).to_string(),
        )
      }
      self.pos = self.pos + 3
    } else {
      name.write_string_utf8(ch.to_string())
      self.pos = self.pos + 1
    }
  }
  let text = name.to_bytes()
  let name = @utf8.decode(text) catch { _ => raise Syntax("bad name", start) }
  if name.length() == 0 {
    raise Syntax("empty name", start)
  }
  name
}

///|
fn Parser::read_hex_digit(self : Parser) -> Int32 raise Refused {
  if self.pos >= self.text.length() {
    raise Syntax("expected a hex digit", self.pos)
  }
  let ch = char_at(self.text, self.pos)
  self.pos = self.pos + 1
  if is_digit(ch) {
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
fn write_utf8(out : Buffer, code : Int32) -> Unit {
  if code < 0x80 {
    out.write_byte(code.to_byte())
  } else if code < 0x800 {
    out.write_byte((0xC0 | (code >> 6)).to_byte())
    out.write_byte((0x80 | (code & 0x3F)).to_byte())
  } else if code < 0x10000 {
    out.write_byte((0xE0 | (code >> 12)).to_byte())
    out.write_byte((0x80 | ((code >> 6) & 0x3F)).to_byte())
    out.write_byte((0x80 | (code & 0x3F)).to_byte())
  } else {
    out.write_byte((0xF0 | (code >> 18)).to_byte())
    out.write_byte((0x80 | ((code >> 12) & 0x3F)).to_byte())
    out.write_byte((0x80 | ((code >> 6) & 0x3F)).to_byte())
    out.write_byte((0x80 | (code & 0x3F)).to_byte())
  }
}

///|
fn Parser::read_string_literal(self : Parser) -> Bytes raise Refused {
  self.skip()
  let start = self.pos
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
      raise Syntax("unterminated string", start)
    }
    let ch = char_at(self.text, self.pos)
    if ch == quote {
      self.pos = self.pos + 1
      return out.to_bytes()
    }
    if ch == '\n' {
      raise Syntax("a string literal cannot span lines", self.pos)
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
      } else if esc == 'a' {
        out.write_byte(0x07)
      } else if esc == 'b' {
        out.write_byte(0x08)
      } else if esc == 'f' {
        out.write_byte(0x0C)
      } else if esc == 'v' {
        out.write_byte(0x0B)
      } else if esc == '?' || esc == '\\' || esc == '\'' || esc == '"' {
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
      } else if esc == 'u' || esc == 'U' {
        let count = if esc == 'u' { 4 } else { 8 }
        let mut code = 0
        for _ in 0..<count {
          code = code * 16 + self.read_hex_digit()
        }
        if code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) {
          raise Syntax("invalid code point in escape", self.pos)
        }
        write_utf8(out, code)
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
/// One string value, which may be several adjacent literals: they are joined,
/// so `'first' "second"` is one value.
fn Parser::read_string(self : Parser) -> Bytes raise Refused {
  let out = Buffer()
  let mut seen = false
  while true {
    match self.peek() {
      Some(ch) =>
        if ch == '"' || ch == '\'' {
          let piece = self.read_string_literal()
          for i in 0..<piece.length() {
            out.write_byte(piece[i])
          }
          seen = true
        } else {
          break
        }
      None => break
    }
  }
  if !seen {
    raise Syntax("expected a string", self.pos)
  }
  out.to_bytes()
}

// -- numbers ----------------------------------------------------------------

///|
/// Split an integer token into sign, base and digits. A leading `0x` selects
/// base 16 and any other leading zero selects base 8, which is what makes
/// `017777777777` the largest int32.
fn integer_parts(token : String) -> (Bool, Int32, String) raise Refused {
  let mut i = 0
  let mut negative = false
  if token.length() > 0 {
    let ch = char_at(token, 0)
    if ch == '-' {
      negative = true
      i = 1
    } else if ch == '+' {
      i = 1
    }
  }
  let mut base = 10
  if token.length() > i + 1 && char_at(token, i) == '0' {
    let next = char_at(token, i + 1)
    if next == 'x' || next == 'X' {
      base = 16
      i = i + 2
    } else {
      base = 8
    }
  }
  if i >= token.length() {
    raise BadValue(token)
  }
  (negative, base, token[i:].to_owned())
}

///|
fn digits_value(digits : String, base : Int32) -> UInt64 raise Refused {
  let limit = 0xFFFF_FFFF_FFFF_FFFFUL
  let radix = base.to_uint64()
  let mut value = 0UL
  for i in 0..<digits.length() {
    let ch = char_at(digits, i)
    let digit = if is_digit(ch) {
      (ch.to_int() - '0'.to_int()).to_uint64()
    } else if ch >= 'a' && ch <= 'f' {
      (ch.to_int() - 'a'.to_int() + 10).to_uint64()
    } else if ch >= 'A' && ch <= 'F' {
      (ch.to_int() - 'A'.to_int() + 10).to_uint64()
    } else {
      raise BadValue(digits)
    }
    if digit >= radix {
      raise BadValue(digits)
    }
    if value > (limit - digit) / radix {
      raise BadValue(digits)
    }
    value = value * radix + digit
  }
  value
}

///|
/// An integer for a field of `kind`, refusing a value the type cannot hold. The
/// limit is checked on the magnitude, so the minimum of a signed type (which
/// has no positive counterpart) is accepted.
fn int_value(
  kind : @reflect.Kind,
  token : String,
) -> @reflect.Value raise Refused {
  let (negative, base, digits) = integer_parts(token)
  let magnitude = digits_value(digits, base)
  match kind {
    @reflect.Int32 | @reflect.Sint32 | @reflect.Sfixed32 => {
      let limit = if negative { 0x8000_0000UL } else { 0x7FFF_FFFFUL }
      if magnitude > limit {
        raise BadValue(token)
      }
      let signed = if negative {
        0L - magnitude.reinterpret_as_int64()
      } else {
        magnitude.reinterpret_as_int64()
      }
      @reflect.Int32(signed.to_int())
    }
    @reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 => {
      let limit = if negative {
        0x8000_0000_0000_0000UL
      } else {
        0x7FFF_FFFF_FFFF_FFFFUL
      }
      if magnitude > limit {
        raise BadValue(token)
      }
      let signed = if negative {
        0L - magnitude.reinterpret_as_int64()
      } else {
        magnitude.reinterpret_as_int64()
      }
      @reflect.Int64(signed)
    }
    @reflect.Uint32 | @reflect.Fixed32 => {
      if (negative && magnitude != 0UL) || magnitude > 0xFFFF_FFFFUL {
        raise BadValue(token)
      }
      @reflect.Uint32(
        magnitude.reinterpret_as_int64().to_int().reinterpret_as_uint(),
      )
    }
    @reflect.Uint64 | @reflect.Fixed64 => {
      if negative && magnitude != 0UL {
        raise BadValue(token)
      }
      @reflect.Uint64(magnitude)
    }
    _ => raise BadValue(token)
  }
}

///|
fn lowercase_word(text : String) -> String {
  let buf = Buffer()
  for i in 0..<text.length() {
    let ch = char_at(text, i)
    if ch >= 'A' && ch <= 'Z' {
      let code = ch.to_int() - 'A'.to_int() + 'a'.to_int()
      buf.write_string_utf8(code.to_char().unwrap_or('a').to_string())
    } else {
      buf.write_string_utf8(ch.to_string())
    }
  }
  let bytes = buf.to_bytes()
  @utf8.decode(bytes) catch {
    _ => text
  }
}

///|
/// The exponent a literal carries, or zero. Used only to decide which way an
/// overflowing literal goes.
fn literal_exponent_is_negative(body : String) -> Bool {
  for i in 0..<body.length() {
    let ch = char_at(body, i)
    if ch == 'e' || ch == 'E' {
      return i + 1 < body.length() && char_at(body, i + 1) == '-'
    }
  }
  false
}

///|
/// A floating point literal. `inf` and `nan` are case-insensitive and take a
/// sign; hex and octal forms are not float literals; a magnitude that does not
/// fit becomes an infinity or a signed zero, as the format specifies.
fn double_value(token : String) -> Double raise Refused {
  let mut i = 0
  let mut negative = false
  if token.length() > 0 {
    let ch = char_at(token, 0)
    if ch == '-' {
      negative = true
      i = 1
    } else if ch == '+' {
      i = 1
    }
  }
  let mut body = token[i:].to_owned()
  if body.length() > 0 {
    let last = char_at(body, body.length() - 1)
    if last == 'f' || last == 'F' {
      body = body[0:body.length() - 1].to_owned()
    }
  }
  let word = lowercase_word(body)
  if word == "inf" || word == "infinity" {
    return if negative { @double.neg_infinity } else { @double.infinity }
  }
  if word == "nan" {
    return @double.not_a_number
  }
  if body.length() == 0 {
    raise BadValue(token)
  }
  for k in 0..<body.length() {
    let ch = char_at(body, k)
    if ch == 'x' || ch == 'X' {
      raise BadValue(token)
    }
  }
  // A leading zero with no fraction and no exponent is an octal integer, which
  // is not a float literal.
  let mut has_marker = false
  for k in 0..<body.length() {
    let ch = char_at(body, k)
    if ch == '.' || ch == 'e' || ch == 'E' {
      has_marker = true
    }
  }
  if !has_marker && body.length() > 1 && char_at(body, 0) == '0' {
    raise BadValue(token)
  }
  let signed = if negative { "-" + body } else { body }
  @string.parse_double(signed) catch {
    _ =>
      // Only a magnitude problem reaches here: the literal is well formed, so
      // the sign of the exponent says which side the value overflowed towards.
      if literal_exponent_is_negative(body) {
        if negative {
          -0.0
        } else {
          0.0
        }
      } else if negative {
        @double.neg_infinity
      } else {
        @double.infinity
      }
  }
}

// -- fields -----------------------------------------------------------------

///|
/// A float literal is either a number or one of the special words, which are
/// identifiers rather than numeric tokens.
fn read_float_token(parser : Parser) -> String raise Refused {
  parser.skip()
  let start = parser.pos
  let mut sign = ""
  match parser.peek() {
    Some('-') => {
      parser.expect('-')
      sign = "-"
    }
    Some('+') => {
      parser.expect('+')
      sign = "+"
    }
    _ => ()
  }
  match parser.peek() {
    Some(ch) =>
      if is_ident_start(ch) {
        sign + parser.read_ident()
      } else {
        parser.pos = start
        parser.read_number_token()
      }
    None => raise Syntax("expected a number", parser.pos)
  }
}

///|
fn is_reserved_name(desc : @reflect.MessageDescriptor, name : String) -> Bool {
  for item in desc.reserved_names {
    if item == name {
      return true
    }
  }
  false
}

///|
/// The field a text name selects. A group field is written with the group's
/// type name or its own field name, in either case, so the last comparison
/// ignores case.
fn find_field(
  desc : @reflect.MessageDescriptor,
  name : String,
) -> @reflect.FieldDescriptor? {
  for field in desc.fields {
    if field.text_name == name {
      return Some(field)
    }
  }
  for field in desc.fields {
    if field.name == name {
      return Some(field)
    }
  }
  for field in desc.fields {
    if field.json_name == name {
      return Some(field)
    }
  }
  let wanted = lowercase_word(name)
  for field in desc.fields {
    if lowercase_word(field.text_name) == wanted ||
      lowercase_word(field.name) == wanted {
      return Some(field)
    }
  }
  None
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
    if parser.peek() == Some('[') {
      let key = parser.read_bracket()
      if parser.peek() == Some(':') {
        parser.expect(':')
      }
      if message.descriptor().full_name == "google.protobuf.Any" &&
        key.contains("/") {
        parse_any_text(message, key, parser, opts, depth)
      } else {
        match @reflect.global_types.find_extension_by_name(key) {
          Some(extension) => {
            let field = extension.descriptor()
            parse_field(message, field, parser, opts, depth)
          }
          None =>
            if !opts.discard_unknown {
              raise UnknownField(key)
            } else {
              skip_value(parser)
            }
        }
      }
    } else {
      let name = parser.read_ident()
      let desc = message.descriptor()
      match find_field(desc, name) {
        Some(field) => {
          // The colon is required before a scalar and optional before a
          // message, so accepting it when present covers both.
          if parser.peek() == Some(':') {
            parser.expect(':')
          }
          parse_field(message, field, parser, opts, depth)
        }
        None =>
          // A name the schema reserves is skipped the way an unknown field is:
          // the message has no field to put it in, and the case is data a reader is
          // allowed to drop.
          if opts.discard_unknown || is_reserved_name(desc, name) {
            if parser.peek() == Some(':') {
              parser.expect(':')
            }
            skip_value(parser)
          } else {
            raise UnknownField(name)
          }
      }
    }
    // One separator may follow a field; a second one leaves `;` or `,` where
    // the next field name belongs, which the next round refuses.
    match parser.peek() {
      Some(';') => parser.expect(';')
      Some(',') => parser.expect(',')
      _ => ()
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
    parse_map_field(message, field, parser, opts, depth)
    return
  }
  if parser.peek() == Some('[') && field.is_list() {
    parser.expect('[')
    if parser.take(']') {
      return
    }
    while true {
      let value = parse_value(field, parser, opts, depth)
      message.mutable(field).list().append(value)
      if parser.take(',') {
        if parser.peek() == Some(']') {
          raise Syntax("trailing comma in a list", parser.pos)
        }
      } else if parser.take(']') {
        return
      } else {
        raise Syntax("expected , or ]", parser.pos)
      }
    }
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
fn parse_map_field(
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  parser : Parser,
  opts : UnmarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
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
    if parser.take('}') {
      break
    }
    let name = parser.read_ident()
    if parser.peek() == Some(':') {
      parser.expect(':')
    }
    if name == key_field.text_name || name == key_field.name {
      key = parse_scalar(key_field, parser, opts, depth)
    } else if name == value_field.text_name || name == value_field.name {
      value = parse_value(value_field, parser, opts, depth)
    } else if opts.discard_unknown {
      skip_value(parser)
    } else {
      raise UnknownField(name)
    }
    if parser.take(',') || parser.take(';') {
      ()
    }
  }
  match key.map_key() {
    Some(map_key) => entry.set(map_key, value)
    None => ()
  }
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
  let _ = opts
  let _ = depth
  match field.kind {
    @reflect.Bool =>
      match parser.peek() {
        Some(ch) =>
          if is_digit(ch) || ch == '-' || ch == '+' {
            let value = int_value(@reflect.Int32, parser.read_number_token())
            match value.int().to_int() {
              0 => @reflect.Bool(false)
              1 => @reflect.Bool(true)
              _ => raise BadValue(field.name)
            }
          } else {
            bool_word(field, parser.read_ident())
          }
        None => raise Syntax("expected a value", parser.pos)
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
    @reflect.Int32
    | @reflect.Sint32
    | @reflect.Sfixed32
    | @reflect.Int64
    | @reflect.Sint64
    | @reflect.Sfixed64
    | @reflect.Uint32
    | @reflect.Fixed32
    | @reflect.Uint64
    | @reflect.Fixed64 => int_value(field.kind, parser.read_number_token())
    @reflect.Float =>
      @reflect.Float(
        @float.Float::from_double(double_value(read_float_token(parser))),
      )
    @reflect.Double => @reflect.Double(double_value(read_float_token(parser)))
    @reflect.Enum => parse_enum(field, parser)
    @reflect.Message | @reflect.Group => raise BadValue(field.name)
  }
}

///|
fn bool_word(
  field : @reflect.FieldDescriptor,
  word : String,
) -> @reflect.Value raise Refused {
  if word == "true" || word == "t" {
    @reflect.Bool(true)
  } else if word == "false" || word == "f" {
    @reflect.Bool(false)
  } else {
    raise BadValue(field.name)
  }
}

///|
/// An enum takes a value name or a number. A number has to name a value of a
/// closed enum; an open enum keeps it, because that is what open means.
fn parse_enum(
  field : @reflect.FieldDescriptor,
  parser : Parser,
) -> @reflect.Value raise Refused {
  let token = match parser.peek() {
    Some(ch) =>
      if is_digit(ch) || ch == '-' || ch == '+' {
        let value = int_value(@reflect.Int32, parser.read_number_token())
        let number = value.int().to_int()
        match enum_descriptor(field) {
          Some(item) =>
            match item.value_by_number(number) {
              None => if item.closed { raise BadValue(field.name) }
              Some(_) => ()
            }
          None => ()
        }
        return @reflect.Enum(number)
      } else {
        parser.read_ident()
      }
    None => raise Syntax("expected an enum value", parser.pos)
  }
  match enum_descriptor(field) {
    Some(item) =>
      match item.value_by_name(token) {
        Some(value) => @reflect.Enum(value.number)
        None => raise BadValue(field.name)
      }
    None => raise BadValue(field.name)
  }
}

///|
fn enum_descriptor(
  field : @reflect.FieldDescriptor,
) -> @reflect.EnumDescriptor? {
  match field.enum_type {
    Some(name) => @reflect.global_files.find_enum_by_name(name)
    None => None
  }
}

///|
fn skip_word(parser : Parser) -> Unit raise Refused {
  match parser.peek() {
    Some(ch) =>
      if is_ident_start(ch) {
        let _ = parser.read_ident()
      } else {
        let _ = parser.read_number_token()
      }
    None => ()
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
    Some('[') => {
      parser.expect('[')
      skip_balanced(parser, ']')
    }
    Some('"') => {
      let _ = parser.read_string()
    }
    Some('\'') => {
      let _ = parser.read_string()
    }
    Some(_) => skip_word(parser)
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
        } else if ch == '[' {
          parser.expect('[')
          skip_balanced(parser, ']')
        } else if ch == ',' || ch == ';' || ch == ':' {
          parser.expect(ch)
        } else if ch == '"' || ch == '\'' {
          let _ = parser.read_string()
        } else {
          skip_word(parser)
        }
    }
  }
}
