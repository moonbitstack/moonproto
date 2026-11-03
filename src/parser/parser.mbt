// A parser for the protocol buffer language, producing the descriptor shape
// `desc` builds from. Covers proto2, proto3 and editions: messages, fields,
// maps, oneofs, groups, enums, services, reserved and extension ranges.
// https://protobuf.dev/programming-guides/proto3/

///|
pub(all) suberror Refused {
  Syntax(String, Int32)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Syntax(message, at) =>
      logger.write_string("syntax at " + at.to_string() + ": " + message)
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
priv struct Parser {
  text : String
  mut pos : Int32
}

///|
fn char_at(text : String, index : Int32) -> Char {
  text[index].to_int().to_char().unwrap_or('?')
}

///|
fn[T] append(items : Array[T], item : T) -> Array[T] {
  let out = items.copy()
  out.push(item)
  out
}

///|
fn Parser::new(text : String) -> Parser {
  { text, pos: 0, }
}

///|
fn Parser::error(self : Parser, message : String) -> Refused {
  Syntax(message, self.pos)
}

///|
fn Parser::skip(self : Parser) -> Unit {
  while self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      self.pos = self.pos + 1
    } else if ch == '/' &&
      self.pos + 1 < self.text.length() &&
      char_at(self.text, self.pos + 1) == '/' {
      self.pos = self.pos + 2
      while self.pos < self.text.length() &&
            char_at(self.text, self.pos) != '\n' {
        self.pos = self.pos + 1
      }
    } else if ch == '/' &&
      self.pos + 1 < self.text.length() &&
      char_at(self.text, self.pos + 1) == '*' {
      self.pos = self.pos + 2
      while self.pos + 1 < self.text.length() &&
            !(char_at(self.text, self.pos) == '*' &&
            char_at(self.text, self.pos + 1) == '/') {
        self.pos = self.pos + 1
      }
      self.pos = self.pos + 2
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
    raise self.error("expected " + ch.to_string())
  }
  self.pos = self.pos + 1
}

///|
fn Parser::accept(self : Parser, ch : Char) -> Bool {
  self.skip()
  if self.pos < self.text.length() && char_at(self.text, self.pos) == ch {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

///|
fn Parser::accept_word(self : Parser, word : String) -> Bool {
  let save = self.pos
  self.skip()
  let token = self.read_ident() catch {
    _ => {
      self.pos = save
      return false
    }
  }
  if token == word {
    true
  } else {
    self.pos = save
    false
  }
}

///|
fn is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

///|
fn is_ident_char(ch : Char) -> Bool {
  is_ident_start(ch) || (ch >= '0' && ch <= '9')
}

///|
fn Parser::read_ident(self : Parser) -> String raise Refused {
  self.skip()
  let start = self.pos
  if self.pos >= self.text.length() ||
    !is_ident_start(char_at(self.text, self.pos)) {
    raise self.error("expected an identifier")
  }
  self.pos = self.pos + 1
  while self.pos < self.text.length() &&
        is_ident_char(char_at(self.text, self.pos)) {
    self.pos = self.pos + 1
  }
  self.text[start:self.pos].to_owned()
}

///|
fn Parser::read_dotted(self : Parser) -> String raise Refused {
  self.skip()
  let mut name = self.read_ident()
  while self.pos < self.text.length() && char_at(self.text, self.pos) == '.' {
    self.pos = self.pos + 1
    name = name + "." + self.read_ident()
  }
  name
}

///|
/// A type name, with an optional leading dot and dots between segments.
fn Parser::read_type_name(self : Parser) -> String raise Refused {
  self.skip()
  let mut name = ""
  if self.accept('.') {
    name = "."
  }
  name = name + self.read_ident()
  while self.pos < self.text.length() && char_at(self.text, self.pos) == '.' {
    self.pos = self.pos + 1
    name = name + "." + self.read_ident()
  }
  name
}

///|
fn Parser::read_string(self : Parser) -> String raise Refused {
  self.skip()
  if self.pos >= self.text.length() {
    raise self.error("expected a string")
  }
  let quote = char_at(self.text, self.pos)
  if quote != '"' && quote != '\'' {
    raise self.error("expected a string")
  }
  self.pos = self.pos + 1
  let out = Buffer()
  while true {
    if self.pos >= self.text.length() {
      raise self.error("unterminated string")
    }
    let ch = char_at(self.text, self.pos)
    if ch == quote {
      self.pos = self.pos + 1
      return @utf8.decode(out.to_bytes()) catch { _ => "" }
    }
    if ch == '\\' {
      self.pos = self.pos + 1
      if self.pos >= self.text.length() {
        raise self.error("unterminated escape")
      }
      let esc = char_at(self.text, self.pos)
      self.pos = self.pos + 1
      if esc == 'n' {
        out.write_byte(0x0A)
      } else if esc == 'r' {
        out.write_byte(0x0D)
      } else if esc == 't' {
        out.write_byte(0x09)
      } else if esc == 'b' {
        out.write_byte(0x08)
      } else if esc == 'f' {
        out.write_byte(0x0C)
      } else if esc == '\\' || esc == '"' || esc == '\'' {
        out.write_byte(esc.to_int().to_byte())
      } else if esc == 'x' || esc == 'X' {
        let high = self.read_hex()
        let low = self.read_hex()
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
        out.write_byte(esc.to_int().to_byte())
      }
    } else {
      let bytes = @utf8.encode(ch.to_string())
      for i in 0..<bytes.length() {
        out.write_byte(bytes[i])
      }
      self.pos = self.pos + 1
    }
  }
  ""
}

///|
fn Parser::read_hex(self : Parser) -> Int32 raise Refused {
  if self.pos >= self.text.length() {
    raise self.error("expected a hex digit")
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
    raise self.error("expected a hex digit")
  }
}

///|
fn hex_value(ch : Char) -> Int64 {
  if ch >= '0' && ch <= '9' {
    (ch.to_int() - '0'.to_int()).to_int64()
  } else if ch >= 'a' && ch <= 'f' {
    (ch.to_int() - 'a'.to_int() + 10).to_int64()
  } else {
    (ch.to_int() - 'A'.to_int() + 10).to_int64()
  }
}

///|
fn Parser::read_int(self : Parser) -> Int32 raise Refused {
  self.skip()
  let negative = self.accept('-')
  self.skip()
  let start = self.pos
  let mut value = 0L
  if self.pos + 1 < self.text.length() &&
    char_at(self.text, self.pos) == '0' &&
    (
      char_at(self.text, self.pos + 1) == 'x' ||
      char_at(self.text, self.pos + 1) == 'X'
    ) {
    self.pos = self.pos + 2
    while self.pos < self.text.length() {
      let ch = char_at(self.text, self.pos)
      if (ch >= '0' && ch <= '9') ||
        (ch >= 'a' && ch <= 'f') ||
        (ch >= 'A' && ch <= 'F') {
        value = value * 16L + hex_value(ch)
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  } else {
    while self.pos < self.text.length() &&
          char_at(self.text, self.pos) >= '0' &&
          char_at(self.text, self.pos) <= '9' {
      value = value * 10L +
        (char_at(self.text, self.pos).to_int() - '0'.to_int()).to_int64()
      self.pos = self.pos + 1
    }
  }
  if self.pos == start {
    raise self.error("expected a number")
  }
  let signed = if negative { -value } else { value }
  signed.to_int()
}

///|
/// Read a balanced `{ ... }` value, skipping over quoted strings so a brace
/// inside one does not close it.
fn Parser::read_aggregate(self : Parser) -> String raise Refused {
  let start = self.pos
  let mut depth = 0
  while self.pos < self.text.length() {
    let ch = char_at(self.text, self.pos)
    if ch == '"' || ch == '\'' {
      let quote = ch
      self.pos = self.pos + 1
      while self.pos < self.text.length() {
        let inner = char_at(self.text, self.pos)
        if inner == '\\' {
          self.pos = self.pos + 2
        } else if inner == quote {
          self.pos = self.pos + 1
          break
        } else {
          self.pos = self.pos + 1
        }
      }
    } else if ch == '{' {
      depth = depth + 1
      self.pos = self.pos + 1
    } else if ch == '}' {
      depth = depth - 1
      self.pos = self.pos + 1
      if depth == 0 {
        return self.text[start:self.pos].to_owned()
      }
    } else {
      self.pos = self.pos + 1
    }
  }
  raise self.error("unterminated option value")
}

///|
fn Parser::read_constant_text(self : Parser) -> String raise Refused {
  self.skip()
  match self.peek() {
    Some('"') | Some('\'') => self.read_string()
    // An aggregate option value, `{ key: value ... }`, is kept as written.
    Some('{') => self.read_aggregate()
    Some(_) => {
      let start = self.pos
      while self.pos < self.text.length() {
        let ch = char_at(self.text, self.pos)
        if (ch >= '0' && ch <= '9') ||
          (ch >= 'a' && ch <= 'z') ||
          (ch >= 'A' && ch <= 'Z') ||
          ch == '-' ||
          ch == '+' ||
          ch == '.' ||
          ch == '_' {
          self.pos = self.pos + 1
        } else {
          break
        }
      }
      self.text[start:self.pos].to_owned()
    }
    None => raise self.error("expected a value")
  }
}

///|
fn scalar_code(name : String) -> Int32? {
  match name {
    "double" => Some(1)
    "float" => Some(2)
    "int64" => Some(3)
    "uint64" => Some(4)
    "int32" => Some(5)
    "fixed64" => Some(6)
    "fixed32" => Some(7)
    "bool" => Some(8)
    "string" => Some(9)
    "bytes" => Some(12)
    "uint32" => Some(13)
    "sfixed32" => Some(15)
    "sfixed64" => Some(16)
    "sint32" => Some(17)
    "sint64" => Some(18)
    _ => None
  }
}

///|
fn label_code(word : String) -> Int32? {
  match word {
    "optional" => Some(1)
    "required" => Some(2)
    "repeated" => Some(3)
    _ => None
  }
}

///|
fn capitalize(name : String) -> String {
  if name.length() == 0 {
    name
  } else {
    let first = char_at(name, 0)
    let upper = if first >= 'a' && first <= 'z' {
      (first.to_int() - 32).to_char().unwrap_or(first)
    } else {
      first
    }
    upper.to_string() + name[1:].to_owned()
  }
}

///|
fn lower_first(name : String) -> String {
  if name.length() == 0 {
    name
  } else {
    let first = char_at(name, 0)
    let lower = if first >= 'A' && first <= 'Z' {
      (first.to_int() + 32).to_char().unwrap_or(first)
    } else {
      first
    }
    lower.to_string() + name[1:].to_owned()
  }
}

///|
fn entry_name(field_name : String) -> String {
  // The descriptor rule: CamelCase of the field name, then "Entry".
  let out = Buffer()
  let mut upper = true
  for i in 0..<field_name.length() {
    let ch = char_at(field_name, i)
    if ch == '_' {
      upper = true
    } else if upper {
      out.write_string_utf8(capitalize(ch.to_string()))
      upper = false
    } else {
      out.write_string_utf8(ch.to_string())
    }
  }
  out.write_string_utf8("Entry")
  @utf8.decode(out.to_bytes()) catch {
    _ => ""
  }
}

///|
fn make_field(
  name : String,
  number : Int32,
  label : Int32,
  type_code : Int32,
  type_name : String?,
  json_name : String?,
  default_value : String?,
  oneof_index : Int32?,
  proto3_optional : Bool,
  packed_off : Bool,
  extendee~ : String? = None,
  features~ : @desc.Features = @desc.features_auto,
  options~ : Array[(String, String)] = [],
) -> @desc.FieldDescriptorProto {
  {
    name,
    number,
    label,
    type_code,
    type_name,
    json_name,
    default_value,
    oneof_index,
    proto3_optional,
    packed_off,
    extendee,
    features,
    options,
  }
}

///|
/// Parse one `.proto` file.
pub fn parse(
  file_name : String,
  text : String,
) -> @desc.FileDescriptorProto raise Refused {
  let parser = Parser::new(text)
  let mut result : @desc.FileDescriptorProto = {
    name: file_name,
    package_name: "",
    syntax: "proto2",
    message_type: [],
    enum_type: [],
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
    edition: None,
    features: @desc.features_auto,
    options: [],
  }
  while !parser.eof() {
    let word = parser.read_ident()
    match word {
      "syntax" => {
        parser.expect('=')
        result = { ..result, syntax: parser.read_string(), }
        parser.expect(';')
      }
      "edition" => {
        parser.expect('=')
        let edition = parser.read_string()
        result = { ..result, syntax: "editions", edition: Some(edition), }
        parser.expect(';')
      }
      "package" => {
        result = { ..result, package_name: parser.read_dotted(), }
        parser.expect(';')
      }
      "import" => {
        let mut public = false
        if parser.peek() == Some('p') {
          let word = parser.read_ident()
          public = word == "public"
        } else if parser.peek() == Some('w') {
          let _ = parser.read_ident()
        }
        let path = parser.read_string()
        parser.expect(';')
        let index = result.dependency.length()
        result = { ..result, dependency: append(result.dependency, path), }
        if public {
          result = {
            ..result,
            public_dependency: append(result.public_dependency, index),
            edition: None,
            features: @desc.features_auto,
            options: [],
          }
        }
      }
      "option" => {
        let name = parser.read_option_name()
        parser.expect('=')
        let value = parser.read_constant_text()
        if name_has_prefix(name, "features.") {
          result = {
            ..result,
            features: result.features.set(
              name[9:name.length()].to_owned(),
              value,
            ),
          }
        } else {
          result = { ..result, options: append(result.options, (name, value)), }
        }
        parser.expect(';')
      }
      "message" => {
        let message = parse_message(
          parser,
          result.package_name,
          result.syntax,
          inherited=result.features,
        )
        result = {
          ..result,
          message_type: append(result.message_type, message),
        }
      }
      "enum" => {
        let item = parse_enum(parser, inherited=result.features)
        result = { ..result, enum_type: append(result.enum_type, item), }
      }
      "service" => {
        let item = parse_service(parser)
        result = { ..result, service: append(result.service, item), }
      }
      "extend" => {
        let extendee = parser.read_type_name()
        parser.expect('{')
        let fields = parse_extend_body(
          parser,
          result.package_name,
          result.syntax,
          extendee,
        )
        for field in fields {
          result = { ..result, extension: append(result.extension, field), }
        }
      }
      ";" => ()
      _ => raise parser.error("unexpected " + word)
    }
  }
  result = resolve_types(result)
  result
}

///|
fn Parser::read_option_name(self : Parser) -> String raise Refused {
  self.skip()
  if self.accept('(') {
    let mut name = "(" + self.read_dotted()
    if self.accept(')') {
      name = name + ")"
    }
    name
  } else {
    self.read_dotted()
  }
}

///|
fn parse_message(
  parser : Parser,
  scope : String,
  syntax : String,
  inherited~ : @desc.Features = @desc.features_auto,
) -> @desc.DescriptorProto raise Refused {
  let name = parser.read_ident()
  parse_message_body(parser, scope, name, syntax, false, inherited~)
}

///|
fn parse_message_body(
  parser : Parser,
  scope : String,
  name : String,
  syntax : String,
  map_entry : Bool,
  inherited~ : @desc.Features = @desc.features_auto,
) -> @desc.DescriptorProto raise Refused {
  let full = if scope.length() == 0 { name } else { scope + "." + name }
  let fields : Array[@desc.FieldDescriptorProto] = []
  let nested : Array[@desc.DescriptorProto] = []
  let enums : Array[@desc.EnumDescriptorProto] = []
  let extensions : Array[@desc.FieldDescriptorProto] = []
  let oneofs : Array[@desc.OneofDescriptorProto] = []
  let reserved_ranges : Array[(Int32, Int32)] = []
  let reserved_names : Array[String] = []
  let extension_ranges : Array[(Int32, Int32)] = []
  let mut is_map_entry = map_entry
  let mut features = inherited
  let options : Array[(String, String)] = []
  parser.expect('{')
  while true {
    parser.skip()
    if parser.eof() {
      raise parser.error("unterminated message")
    }
    if parser.accept('}') {
      break
    }
    if parser.accept(';') {
      continue
    }
    let start = parser.pos
    let word = parser.read_ident()
    match word {
      "message" => {
        let item = parse_message(parser, full, syntax, inherited=features)
        nested.push(item)
      }
      "enum" => {
        let item = parse_enum(parser, inherited=features)
        enums.push(item)
      }
      "oneof" => {
        let oneof_name = parser.read_ident()
        let index = oneofs.length()
        oneofs.push({ name: oneof_name, })
        parser.expect('{')
        while true {
          parser.skip()
          if parser.accept('}') {
            break
          }
          if parser.accept(';') {
            continue
          }
          let (field, synthesized) = parse_field(
            parser,
            full,
            syntax,
            Some(index),
            inherited=features,
          )
          fields.push(field)
          for item in synthesized {
            nested.push(item)
          }
        }
      }
      "reserved" => {
        parser.pos = start
        let (ranges, names) = parse_reserved(parser)
        for range in ranges {
          reserved_ranges.push(range)
        }
        for item in names {
          reserved_names.push(item)
        }
      }
      "extensions" => {
        parser.pos = start
        let ranges = parse_extensions(parser)
        for range in ranges {
          extension_ranges.push(range)
        }
      }
      "option" => {
        parser.pos = start
        let _ = parser.read_ident()
        let name = parser.read_option_name()
        parser.expect('=')
        let value = parser.read_constant_text()
        if name == "map_entry" && value == "true" {
          is_map_entry = true
        } else if name_has_prefix(name, "features.") {
          features = features.set(name[9:name.length()].to_owned(), value)
        } else {
          options.push((name, value))
        }
        parser.expect(';')
      }
      "extend" => {
        parser.pos = start
        let _ = parser.read_ident()
        let extendee = parser.read_type_name()
        parser.expect('{')
        let items = parse_extend_body(parser, full, syntax, extendee)
        for item in items {
          extensions.push(item)
        }
      }
      _ => {
        parser.pos = start
        let (field, synthesized) = parse_field(
          parser,
          full,
          syntax,
          None,
          inherited=features,
        )
        fields.push(field)
        for item in synthesized {
          nested.push(item)
        }
      }
    }
  }
  {
    name,
    field: fields,
    nested_type: nested,
    enum_type: enums,
    extension: extensions,
    oneof_decl: oneofs,
    reserved_range: reserved_ranges,
    reserved_name: reserved_names,
    extension_range: extension_ranges,
    map_entry: is_map_entry,
    features,
    options,
  }
}

///|
fn parse_field(
  parser : Parser,
  scope : String,
  syntax : String,
  oneof_index : Int32?,
  inherited~ : @desc.Features = @desc.features_auto,
) -> (@desc.FieldDescriptorProto, Array[@desc.DescriptorProto]) raise Refused {
  parser.skip()
  let start = parser.pos
  let first = parser.read_ident()
  let label = match label_code(first) {
    Some(code) => code
    None => {
      parser.pos = start
      let type_name = parser.read_type_name()
      if type_name == "map" && parser.peek() == Some('<') {
        return parse_map_field(parser, scope, syntax, 1, oneof_index)
      }
      return (
        parse_field_tail(
          parser,
          scope,
          syntax,
          1,
          type_name,
          oneof_index,
          false,
          inherited~,
        ),
        [],
      )
    }
  }
  let word = parser.read_ident()
  if word == "group" {
    return parse_group(parser, scope, syntax, label, oneof_index)
  }
  if word == "map" && parser.peek() == Some('<') {
    return parse_map_field(parser, scope, syntax, label, oneof_index)
  }
  let type_name = if word == "map" {
    "map"
  } else if parser.pos > 0 && word.length() > 0 {
    // A dotted type may continue after the first segment.
    let mut name = word
    while parser.peek() == Some('.') {
      parser.expect('.')
      name = name + "." + parser.read_ident()
    }
    name
  } else {
    word
  }
  (
    parse_field_tail(
      parser,
      scope,
      syntax,
      label,
      type_name,
      oneof_index,
      false,
      inherited~,
    ),
    [],
  )
}

///|
fn parse_field_tail(
  parser : Parser,
  scope : String,
  syntax : String,
  label : Int32,
  type_word : String,
  oneof_index : Int32?,
  is_group : Bool,
  inherited~ : @desc.Features = @desc.features_auto,
) -> @desc.FieldDescriptorProto raise Refused {
  let name = parser.read_ident()
  parser.expect('=')
  let number = parser.read_int()
  let (json_name, default_value, packed_off, features, options) = parse_field_options(
    parser,
  )
  parser.expect(';')
  let scalar = scalar_code(type_word)
  let (type_code, type_name) = match scalar {
    Some(code) => (code, None)
    None => (if is_group { 10 } else { 0 }, Some(type_word))
  }
  let proto3_optional = syntax == "proto3" && label == 1 && oneof_index is None
  let _ = scope
  make_field(
    lower_first_if_group(name, is_group),
    number,
    label,
    type_code,
    type_name,
    json_name,
    default_value,
    oneof_index,
    proto3_optional,
    packed_off,
    extendee=None,
    features=@desc.Features::merge(inherited, features),
    options~,
  )
}

///|
fn lower_first_if_group(name : String, is_group : Bool) -> String {
  if is_group {
    lower_first(name)
  } else {
    name
  }
}

///|
fn name_has_prefix(name : String, prefix : String) -> Bool {
  if name.length() < prefix.length() {
    return false
  }
  name[:prefix.length()] == prefix
}

///|
fn parse_field_options(
  parser : Parser,
) -> (String?, String?, Bool, @desc.Features, Array[(String, String)]) raise Refused {
  let mut json_name : String? = None
  let mut default_value : String? = None
  let mut packed_off = false
  let mut features = @desc.features_auto
  let options : Array[(String, String)] = []
  if parser.accept('[') {
    while true {
      let key = parser.read_option_name()
      parser.expect('=')
      let value = parser.read_constant_text()
      if key == "json_name" {
        json_name = Some(value)
      } else if key == "default" {
        default_value = Some(value)
      } else if key == "packed" {
        packed_off = value != "true"
      } else if name_has_prefix(key, "features.") {
        features = features.set(key[9:key.length()].to_owned(), value)
      } else {
        options.push((key, value))
      }
      if !parser.accept(',') {
        break
      }
    }
    parser.expect(']')
  }
  (json_name, default_value, packed_off, features, options)
}

///|
fn parse_map_field(
  parser : Parser,
  scope : String,
  _syntax : String,
  _label : Int32,
  oneof_index : Int32?,
) -> (@desc.FieldDescriptorProto, Array[@desc.DescriptorProto]) raise Refused {
  let _ = oneof_index
  parser.expect('<')
  let key_type = parser.read_type_name()
  parser.expect(',')
  let value_type = parser.read_type_name()
  parser.expect('>')
  let name = parser.read_ident()
  parser.expect('=')
  let number = parser.read_int()
  let (json_name, default_value, packed_off, _features, _options) = parse_field_options(
    parser,
  )
  parser.expect(';')
  let entry = entry_name(name)
  let entry_full = if scope.length() == 0 { entry } else { scope + "." + entry }
  let key_field = make_field(
    "key",
    1,
    1,
    match scalar_code(key_type) {
      Some(code) => code
      None => 0
    },
    match scalar_code(key_type) {
      Some(_) => None
      None => Some(key_type)
    },
    None,
    None,
    None,
    false,
    false,
  )
  let value_field = make_field(
    "value",
    2,
    1,
    match scalar_code(value_type) {
      Some(code) => code
      None => 0
    },
    match scalar_code(value_type) {
      Some(_) => None
      None => Some(value_type)
    },
    None,
    None,
    None,
    false,
    false,
  )
  let entry_message : @desc.DescriptorProto = {
    name: entry,
    field: [key_field, value_field],
    nested_type: [],
    enum_type: [],
    extension: [],
    oneof_decl: [],
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry: true,
    features: @desc.features_auto,
    options: [],
  }
  let field = make_field(
    name,
    number,
    3,
    11,
    Some(entry_full),
    json_name,
    default_value,
    None,
    false,
    packed_off,
    extendee=None,
  )
  (field, [entry_message])
}

///|
fn parse_group(
  parser : Parser,
  scope : String,
  syntax : String,
  label : Int32,
  oneof_index : Int32?,
) -> (@desc.FieldDescriptorProto, Array[@desc.DescriptorProto]) raise Refused {
  let group_name = parser.read_ident()
  parser.expect('=')
  let number = parser.read_int()
  let (json_name, default_value, packed_off, _features, _options) = parse_field_options(
    parser,
  )
  let body = parse_message_body(parser, scope, group_name, syntax, false)
  (
    make_field(
      lower_first(group_name),
      number,
      label,
      10,
      Some(group_name),
      json_name,
      default_value,
      oneof_index,
      false,
      packed_off,
      extendee=None,
    ),
    [body],
  )
}

///|
fn parse_enums_value(
  parser : Parser,
) -> @desc.EnumValueDescriptorProto raise Refused {
  let name = parser.read_ident()
  parser.expect('=')
  let number = parser.read_int()
  let _ = parse_field_options(parser)
  parser.expect(';')
  { name, number, }
}

///|
fn parse_enum(
  parser : Parser,
  inherited~ : @desc.Features = @desc.features_auto,
) -> @desc.EnumDescriptorProto raise Refused {
  let name = parser.read_ident()
  let values : Array[@desc.EnumValueDescriptorProto] = []
  parser.expect('{')
  let mut features = inherited
  let options : Array[(String, String)] = []
  while true {
    parser.skip()
    if parser.eof() {
      raise parser.error("unterminated enum")
    }
    if parser.accept('}') {
      break
    }
    if parser.accept(';') {
      continue
    }
    let start = parser.pos
    let word = parser.read_ident()
    if word == "option" {
      parser.pos = start
      let _ = parser.read_ident()
      let name = parser.read_option_name()
      parser.expect('=')
      let value = parser.read_constant_text()
      if name_has_prefix(name, "features.") {
        features = features.set(name[9:name.length()].to_owned(), value)
      } else {
        options.push((name, value))
      }
      parser.expect(';')
    } else if word == "reserved" {
      parser.pos = start
      let (_, names) = parse_reserved_names_only(parser)
      let _ = names
    } else {
      parser.pos = start
      values.push(parse_enums_value(parser))
    }
  }
  { name, value: values, features, options, }
}

///|
fn parse_service(parser : Parser) -> @desc.ServiceDescriptorProto raise Refused {
  let name = parser.read_ident()
  let methods : Array[@desc.MethodDescriptorProto] = []
  parser.expect('{')
  while true {
    parser.skip()
    if parser.eof() {
      raise parser.error("unterminated service")
    }
    if parser.accept('}') {
      break
    }
    if parser.accept(';') {
      continue
    }
    let start = parser.pos
    let word = parser.read_ident()
    if word == "option" {
      parser.pos = start
      let _ = parser.read_ident()
      let _ = parser.read_option_name()
      parser.expect('=')
      let _ = parser.read_constant_text()
      parser.expect(';')
    } else if word == "rpc" {
      let method_name = parser.read_ident()
      parser.expect('(')
      let client_streaming = parser.accept_word("stream")
      let input_type = parser.read_type_name()
      parser.expect(')')
      let returns = parser.read_ident()
      if returns != "returns" {
        raise parser.error("expected returns")
      }
      parser.expect('(')
      let server_streaming = parser.accept_word("stream")
      let output_type = parser.read_type_name()
      parser.expect(')')
      if parser.accept('{') {
        let mut depth = 1
        while depth > 0 {
          parser.skip()
          if parser.eof() {
            raise parser.error("unterminated rpc")
          }
          if parser.accept('{') {
            depth = depth + 1
          } else if parser.accept('}') {
            depth = depth - 1
          } else {
            parser.pos = parser.pos + 1
          }
        }
      } else {
        parser.expect(';')
      }
      methods.push({
        name: method_name,
        input_type,
        output_type,
        client_streaming,
        server_streaming,
      })
    } else {
      raise parser.error("unexpected " + word)
    }
  }
  { name, methods, }
}

///|
fn parse_ranges(parser : Parser) -> Array[(Int32, Int32)] raise Refused {
  let out : Array[(Int32, Int32)] = []
  while true {
    let start = parser.read_int()
    let mut end = start + 1
    if parser.peek() == Some('t') {
      let word = parser.read_ident()
      if word == "to" {
        if parser.peek() == Some('m') {
          let max = parser.read_ident()
          if max == "max" {
            end = 536870912
          }
        } else {
          end = parser.read_int() + 1
        }
      }
    }
    out.push((start, end))
    if !parser.accept(',') {
      break
    }
  }
  parser.expect(';')
  out
}

///|
fn parse_extensions(parser : Parser) -> Array[(Int32, Int32)] raise Refused {
  let word = parser.read_ident()
  if word != "extensions" {
    raise parser.error("expected extensions")
  }
  parse_ranges(parser)
}

///|
fn parse_reserved(
  parser : Parser,
) -> (Array[(Int32, Int32)], Array[String]) raise Refused {
  let word = parser.read_ident()
  if word != "reserved" {
    raise parser.error("expected reserved")
  }
  let ranges : Array[(Int32, Int32)] = []
  let names : Array[String] = []
  if parser.peek() == Some('"') || parser.peek() == Some('\'') {
    while true {
      names.push(parser.read_string())
      if !parser.accept(',') {
        break
      }
    }
    parser.expect(';')
  } else {
    while true {
      let start = parser.read_int()
      let mut end = start + 1
      if parser.peek() == Some('t') {
        let word = parser.read_ident()
        if word == "to" {
          if parser.peek() == Some('m') {
            let max = parser.read_ident()
            if max == "max" {
              end = 536870912
            }
          } else {
            end = parser.read_int() + 1
          }
        }
      }
      ranges.push((start, end))
      if !parser.accept(',') {
        break
      }
    }
    parser.expect(';')
  }
  (ranges, names)
}

///|
fn parse_reserved_names_only(
  parser : Parser,
) -> (Array[(Int32, Int32)], Array[String]) {
  let word = parser.read_ident() catch { _ => return ([], []) }
  if word != "reserved" {
    return ([], [])
  }
  let ranges : Array[(Int32, Int32)] = []
  let names : Array[String] = []
  if parser.peek() == Some('"') || parser.peek() == Some('\'') {
    while true {
      names.push(parser.read_string() catch { _ => break })
      if !parser.accept(',') {
        break
      }
    }
    parser.expect(';') catch {
      _ => ()
    }
  } else {
    while true {
      let start = parser.read_int() catch { _ => 0 }
      ranges.push((start, start + 1))
      if !parser.accept(',') {
        break
      }
    }
    parser.expect(';') catch {
      _ => ()
    }
  }
  (ranges, names)
}

///|
fn parse_extend_body(
  parser : Parser,
  scope : String,
  syntax : String,
  extendee : String,
) -> Array[@desc.FieldDescriptorProto] raise Refused {
  let fields : Array[@desc.FieldDescriptorProto] = []
  while true {
    parser.skip()
    if parser.accept('}') {
      break
    }
    if parser.accept(';') {
      continue
    }
    let (field, _) = parse_field(parser, scope, syntax, None)
    fields.push({ ..field, extendee: Some(extendee), })
  }
  fields
}

// -- type resolution --------------------------------------------------------

///|
fn collect_type_symbols(
  file : @desc.FileDescriptorProto,
) -> (Array[String], Array[String]) {
  let messages : Array[String] = []
  let enums : Array[String] = []
  for message in file.message_type {
    collect_message_symbols(message, file.package_name, messages, enums)
  }
  for item in file.enum_type {
    enums.push(
      if file.package_name.length() == 0 {
        item.name
      } else {
        file.package_name + "." + item.name
      },
    )
  }
  (messages, enums)
}

///|
fn collect_message_symbols(
  message : @desc.DescriptorProto,
  scope : String,
  messages : Array[String],
  enums : Array[String],
) -> Unit {
  let full = if scope.length() == 0 {
    message.name
  } else {
    scope + "." + message.name
  }
  messages.push(full)
  for nested in message.nested_type {
    collect_message_symbols(nested, full, messages, enums)
  }
  for item in message.enum_type {
    enums.push(full + "." + item.name)
  }
}

///|
fn resolve_name(
  name : String,
  scope : String,
  messages : Array[String],
  enums : Array[String],
) -> (String, Bool) {
  if name.length() > 0 && char_at(name, 0) == '.' {
    let stripped = name[1:].to_owned()
    return (stripped, enums.contains(stripped))
  }
  let mut prefix = scope
  while true {
    let candidate = if prefix.length() == 0 {
      name
    } else {
      prefix + "." + name
    }
    if enums.contains(candidate) {
      return (candidate, true)
    }
    if messages.contains(candidate) {
      return (candidate, false)
    }
    if !prefix.contains(".") {
      break
    }
    prefix = parent_of(prefix)
  }
  if enums.contains(name) {
    return (name, true)
  }
  if messages.contains(name) {
    return (name, false)
  }
  (name, false)
}

///|
fn parent_of(full : String) -> String {
  let mut last = -1
  for i in 0..<full.length() {
    if char_at(full, i) == '.' {
      last = i
    }
  }
  if last < 0 {
    ""
  } else {
    full[:last].to_owned()
  }
}

///|
fn resolve_types(file : @desc.FileDescriptorProto) -> @desc.FileDescriptorProto {
  let (messages, enums) = collect_type_symbols(file)
  let fixed : Array[@desc.DescriptorProto] = []
  for message in file.message_type {
    fixed.push(resolve_message(message, file.package_name, messages, enums))
  }
  { ..file, message_type: fixed, }
}

///|
fn resolve_message(
  message : @desc.DescriptorProto,
  scope : String,
  messages : Array[String],
  enums : Array[String],
) -> @desc.DescriptorProto {
  let full = if scope.length() == 0 {
    message.name
  } else {
    scope + "." + message.name
  }
  let fields : Array[@desc.FieldDescriptorProto] = []
  for field in message.field {
    fields.push(resolve_field(field, full, messages, enums))
  }
  let nested : Array[@desc.DescriptorProto] = []
  for item in message.nested_type {
    nested.push(resolve_message(item, full, messages, enums))
  }
  let extensions : Array[@desc.FieldDescriptorProto] = []
  for field in message.extension {
    extensions.push(resolve_field(field, full, messages, enums))
  }
  { ..message, field: fields, nested_type: nested, extension: extensions, }
}

///|
fn resolve_field(
  field : @desc.FieldDescriptorProto,
  scope : String,
  messages : Array[String],
  enums : Array[String],
) -> @desc.FieldDescriptorProto {
  if field.type_code != 0 {
    return field
  }
  let name = match field.type_name {
    Some(name) => name
    None => return field
  }
  let (resolved, is_enum) = resolve_name(name, scope, messages, enums)
  {
    ..field,
    type_code: if is_enum {
      14
    } else {
      11
    },
    type_name: Some(resolved),
  }
}
