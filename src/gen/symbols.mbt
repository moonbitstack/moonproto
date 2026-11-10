// The table that turns a fully-qualified proto name into the MoonBit type the
// generated source names. A file's fields may refer to types another file
// declares, so the table is built over every file in the request, not one.

///|
/// Where a generated type lives: the package directory its file lands in, and
/// the type name inside it.
pub(all) struct TypeRef {
  dir : String
  name : String
}

///|
/// Fully-qualified proto name to generated type.
pub struct Symbols {
  types : Map[String, TypeRef]
}

///|
/// An empty table; `add_file` fills it, one file at a time.
pub fn Symbols::new() -> Symbols {
  { types: Map([]), }
}

///|
/// Record every message and enum one file declares, including the nested ones.
/// A map entry is recorded too: a field that names it is a map, and the field's
/// emitter asks for the entry's value type by name.
pub fn Symbols::add_file(
  self : Symbols,
  file : @desc.FileDescriptorProto,
) -> Unit {
  let dir = file_dir(file.name)
  for message in file.message_type {
    self.add_message(message, "", file.package_name, dir)
  }
  for item in file.enum_type {
    let full = qualified(file.package_name, item.name)
    self.types.set(full, { dir, name: type_ident(item.name), })
  }
}

///|
fn Symbols::add_message(
  self : Symbols,
  message : @desc.DescriptorProto,
  prefix : String,
  scope : String,
  dir : String,
) -> Unit {
  let name = type_ident(wrapper_name(prefix, message.name))
  let full = qualified(scope, message.name)
  self.types.set(full, { dir, name, })
  for item in message.enum_type {
    self.types.set(qualified(full, item.name), {
      dir,
      name: type_ident(wrapper_name(name, item.name)),
    })
  }
  for nested in message.nested_type {
    self.add_message(nested, name, full, dir)
  }
}

///|
fn qualified(scope : String, name : String) -> String {
  if scope.length() == 0 {
    name
  } else {
    scope + "." + name
  }
}

///|
fn Symbols::find(self : Symbols, full_name : String) -> TypeRef? {
  self.types.get(strip_dot(full_name))
}

///|
/// A descriptor's type reference is written the way the compiler spells it,
/// with a leading dot; the table keys it without one.
fn strip_dot(name : String) -> String {
  if name.length() > 0 && name[0].to_int().to_char().unwrap_or('x') == '.' {
    name[1:].to_owned()
  } else {
    name
  }
}

///|
/// How one generated file names the types it refers to: bare when they live in
/// the same package, qualified by an prefix when they do not.
pub struct Naming {
  dir : String
  symbols : Symbols
  /// Imported package directories, in first-use order, and the prefix each one
  /// is referred to by.
  imports : Array[(String, String)]
}

///|
pub fn Naming::new(dir : String, symbols : Symbols) -> Naming {
  { dir, symbols, imports: [], }
}

///|
fn Naming::alias_for(self : Naming, dir : String) -> String {
  for pair in self.imports {
    if pair.0 == dir {
      return pair.1
    }
  }
  let mut last = ""
  for i in 0..<dir.length() {
    let ch = dir[i].to_int().to_char().unwrap_or('x')
    if ch == '/' {
      last = ""
    } else if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' {
      last = last + ch.to_string()
    }
  }
  let mut prefix = if last.length() == 0 { "dep" } else { last }
  if prefix[0].to_int().to_char().unwrap_or('a') >= '0' &&
    prefix[0].to_int().to_char().unwrap_or('a') <= '9' {
    prefix = "p" + prefix
  }
  let mut unique = prefix
  let mut index = 1
  while has_alias(self.imports, unique) {
    unique = prefix + index.to_string()
    index = index + 1
  }
  self.imports.push((dir, unique))
  unique
}

///|
fn has_alias(imports : Array[(String, String)], prefix : String) -> Bool {
  for pair in imports {
    if pair.1 == prefix {
      return true
    }
  }
  false
}

///|
/// The MoonBit expression that names a proto type.
fn Naming::type_name(self : Naming, full_name : String) -> String raise Refused {
  match self.symbols.find(full_name) {
    Some(found) =>
      if found.dir == self.dir {
        found.name
      } else {
        "@" + self.alias_for(found.dir) + "." + found.name
      }
    None => raise Unknown(strip_dot(full_name))
  }
}
