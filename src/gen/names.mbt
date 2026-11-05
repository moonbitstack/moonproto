// Names the generator gives to a proto declaration, and the MoonBit type a
// field is stored in. A name has to be stable across runs because it appears in
// the generated source, and it has to avoid the words the language owns.

///|
/// MoonBit's reserved words cannot be field names, so a field called `type`
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
    "set_unknown", "to_json", "from_json", "message", "new", "fresh", "unknown_fields",
    "extension_values",
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
/// A message named after a MoonBit built-in type would shadow it, so the
/// generated name takes a suffix. `google.protobuf.Option` is the case that
/// exists in the wild.
fn type_ident(name : String) -> String {
  let reserved : Array[String] = [
    "Option", "Result", "String", "StringView", "Bytes", "BytesView", "Array", "FixedArray",
    "Map", "Int", "Int64", "UInt", "UInt64", "Double", "Float", "Bool", "Unit", "Char",
    "Byte", "Error", "Json", "Buffer", "Logger", "Show", "Eq", "Compare", "Hash",
    "Default", "ToJson", "FromJson", "Iter", "Iterator",
  ]
  if reserved.contains(name) {
    name + "_"
  } else {
    name
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
  upper.to_string() + name[1:].to_owned()
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
/// The directory part of a proto file's path, which is also the MoonBit
/// package its generated code lands in.
fn file_dir(path : String) -> String {
  let mut at = -1
  for i in 0..<path.length() {
    if path[i].to_int().to_char().unwrap_or('x') == '/' {
      at = i
    }
  }
  if at < 0 {
    ""
  } else {
    path[:at].to_owned()
  }
}
