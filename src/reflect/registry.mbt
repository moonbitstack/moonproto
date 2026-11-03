// The two registries: files by path and declaration, and types by name. The
// global pair is what a generated file registers into at module load.

///|
/// A registry refusal: a name already taken.
pub(all) suberror Refused {
  Conflict(String)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Conflict(name) => logger.write_string("already registered: " + name)
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// File descriptors, looked up by path or by a declaration's qualified name.
pub struct Files {
  files : Array[FileDescriptor]
}

///|
pub fn Files::new() -> Files {
  { files: [], }
}

///|
pub fn Files::register(
  self : Files,
  file : FileDescriptor,
) -> Unit raise Refused {
  for existing in self.files {
    if existing.path == file.path {
      raise Conflict(file.path)
    }
  }
  self.files.push(file)
}

///|
pub fn Files::length(self : Files) -> Int32 {
  self.files.length()
}

///|
pub fn Files::all(self : Files) -> Array[FileDescriptor] {
  self.files
}

///|
pub fn Files::find_file_by_path(self : Files, path : String) -> FileDescriptor? {
  for file in self.files {
    if file.path == path {
      return Some(file)
    }
  }
  None
}

///|
pub fn Files::find_message_by_name(
  self : Files,
  name : String,
) -> MessageDescriptor? {
  for file in self.files {
    match find_message_in(file.messages, name) {
      Some(message) => return Some(message)
      None => ()
    }
  }
  None
}

///|
fn find_message_in(
  messages : Array[MessageDescriptor],
  name : String,
) -> MessageDescriptor? {
  for message in messages {
    if message.full_name == name {
      return Some(message)
    }
    match find_message_in(message.nested_messages, name) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
pub fn Files::find_enum_by_name(self : Files, name : String) -> EnumDescriptor? {
  for file in self.files {
    match find_enum_in(file.enums, name) {
      Some(found) => return Some(found)
      None => ()
    }
    for message in file.messages {
      match find_enum_in(message.nested_enums, name) {
        Some(found) => return Some(found)
        None => ()
      }
    }
  }
  None
}

///|
fn find_enum_in(
  enums : Array[EnumDescriptor],
  name : String,
) -> EnumDescriptor? {
  for item in enums {
    if item.full_name == name {
      return Some(item)
    }
  }
  None
}

///|
/// Message, enum and extension types, looked up by qualified name.
pub struct Types {
  messages : Array[(String, &MessageType)]
  enums : Array[(String, &EnumType)]
  extensions : Array[(String, &ExtensionType)]
  extensions_by_number : Array[(String, &ExtensionType)]
}

///|
pub fn Types::new() -> Types {
  { messages: [], enums: [], extensions: [], extensions_by_number: [], }
}

///|
fn lookup_message(
  entries : Array[(String, &MessageType)],
  name : String,
) -> &MessageType? {
  for entry in entries {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
fn lookup_enum(
  entries : Array[(String, &EnumType)],
  name : String,
) -> &EnumType? {
  for entry in entries {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
fn lookup_extension(
  entries : Array[(String, &ExtensionType)],
  name : String,
) -> &ExtensionType? {
  for entry in entries {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn Types::register_message(
  self : Types,
  message : &MessageType,
) -> Unit raise Refused {
  let name = message.descriptor().full_name
  if lookup_message(self.messages, name) is Some(_) {
    raise Conflict(name)
  }
  self.messages.push((name, message))
}

///|
pub fn Types::register_enum(
  self : Types,
  item : &EnumType,
) -> Unit raise Refused {
  let name = item.descriptor().full_name
  if lookup_enum(self.enums, name) is Some(_) {
    raise Conflict(name)
  }
  self.enums.push((name, item))
}

///|
pub fn Types::register_extension(
  self : Types,
  item : &ExtensionType,
) -> Unit raise Refused {
  let field = item.descriptor()
  if lookup_extension(self.extensions, field.full_name) is Some(_) {
    raise Conflict(field.full_name)
  }
  self.extensions.push((field.full_name, item))
  let key = extension_key(field.containing_message, field.number)
  self.extensions_by_number.push((key, item))
}

///|
fn extension_key(message : String, number : Int32) -> String {
  message + "#" + number.to_string()
}

///|
pub fn Types::find_message_by_name(
  self : Types,
  name : String,
) -> &MessageType? {
  lookup_message(self.messages, name)
}

///|
pub fn Types::find_enum_by_name(self : Types, name : String) -> &EnumType? {
  lookup_enum(self.enums, name)
}

///|
pub fn Types::find_extension_by_name(
  self : Types,
  name : String,
) -> &ExtensionType? {
  lookup_extension(self.extensions, name)
}

///|
pub fn Types::find_extension_by_number(
  self : Types,
  message : String,
  number : Int32,
) -> &ExtensionType? {
  lookup_extension(self.extensions_by_number, extension_key(message, number))
}

///|
pub fn Types::num_messages(self : Types) -> Int32 {
  self.messages.length()
}

///|
pub fn Types::num_enums(self : Types) -> Int32 {
  self.enums.length()
}

///|
pub fn Types::num_extensions(self : Types) -> Int32 {
  self.extensions.length()
}

///|
pub fn Types::range_messages(self : Types, f : (&MessageType) -> Bool) -> Unit {
  for entry in self.messages {
    if !f(entry.1) {
      break
    }
  }
}

///|
pub fn Types::range_enums(self : Types, f : (&EnumType) -> Bool) -> Unit {
  for entry in self.enums {
    if !f(entry.1) {
      break
    }
  }
}

///|
pub fn Types::range_extensions(
  self : Types,
  f : (&ExtensionType) -> Bool,
) -> Unit {
  for entry in self.extensions {
    if !f(entry.1) {
      break
    }
  }
}

///|
/// The process-wide registries a generated file registers into.
pub let global_files : Files = Files::new()

///|
pub let global_types : Types = Types::new()
