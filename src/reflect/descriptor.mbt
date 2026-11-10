// Descriptors are plain data: the structure a file declares, with cross-type
// references kept as fully-qualified names. A name is resolved through a
// registry at the moment a value is built, which is what keeps a file's
// declarations from needing pointers back to one another.

///|
/// One value an enum declares: the short name a schema writes, its number, and
/// the qualified name that includes the enum.
pub(all) struct EnumValueDescriptor {
  name : String
  number : Int32
  full_name : String
}

///|
/// An enum: the values it declares, and whether it is closed. A closed enum
/// refuses a number it does not declare; an open one carries it through, which
/// is what lets a sender add values without breaking an older reader.
pub(all) struct EnumDescriptor {
  name : String
  full_name : String
  values : Array[EnumValueDescriptor]
  closed : Bool
  file_path : String
}

///|
/// The value with `number`, or `None`.
pub fn EnumDescriptor::value_by_number(
  self : EnumDescriptor,
  number : Int32,
) -> EnumValueDescriptor? {
  for value in self.values {
    if value.number == number {
      return Some(value)
    }
  }
  None
}

///|
/// The value with `name`, or `None`.
pub fn EnumDescriptor::value_by_name(
  self : EnumDescriptor,
  name : String,
) -> EnumValueDescriptor? {
  for value in self.values {
    if value.name == name {
      return Some(value)
    }
  }
  None
}

///|
/// A set of fields of which at most one holds a value. A synthetic oneof is how
/// a field with the `optional` keyword is declared: it has exactly one member
/// and is not a choice a reader sees.
pub(all) struct OneofDescriptor {
  name : String
  synthetic : Bool
  /// The field numbers that belong to this oneof, in declaration order.
  field_numbers : Array[Int32]
}

///|
/// One field: the number that identifies it on the wire, its kind, how often it
/// may appear, its two names, and the types it refers to by qualified name.
///
/// A map field is not a kind of its own: it is a repeated field whose element is
/// a generated entry message, so `is_map` says which reading applies and
/// `map_key_field` and `map_value_field` describe the entry.
pub(all) struct FieldDescriptor {
  name : String
  full_name : String
  number : Int32
  kind : Kind
  cardinality : Cardinality
  json_name : String
  text_name : String
  /// Whether the field records that it was set. A field with presence keeps an
  /// explicit zero; a field without presence is on the wire only when its value
  /// is not the zero of its kind, because the wire cannot tell an explicit zero
  /// from a field that was never mentioned.
  has_presence : Bool
  /// Whether the field was declared as an extension rather than inside the
  /// message it belongs to.
  is_extension : Bool
  is_map : Bool
  packed : Bool
  /// The index of the oneof this field belongs to, when it belongs to one.
  oneof_index : Int32?
  /// The fully-qualified message type for `Message` and `Group` fields.
  message_type : String?
  /// The fully-qualified enum type for `Enum` fields.
  enum_type : String?
  has_default : Bool
  default_value : Value
  default_enum_name : String?
  /// The fully-qualified name of the message this field belongs to.
  containing_message : String
  /// For a map field, the entry's key and value descriptors.
  map_key_field : FieldDescriptor?
  map_value_field : FieldDescriptor?
}

///|
/// Whether the field is repeated and not a map, so its value is a list.
pub fn FieldDescriptor::is_list(self : FieldDescriptor) -> Bool {
  self.cardinality == Repeated && !self.is_map
}

///|
/// Whether the field is a map, so its value is a map rather than a list.
pub fn FieldDescriptor::is_map_field(self : FieldDescriptor) -> Bool {
  self.is_map
}

///|
/// A message: its fields, the oneofs they belong to, the numbers and names it
/// reserves, the ranges an extension may occupy, and its nested declarations.
/// A map entry is a message like any other with `is_map_entry` set.
pub(all) struct MessageDescriptor {
  name : String
  full_name : String
  syntax : Syntax
  fields : Array[FieldDescriptor]
  oneofs : Array[OneofDescriptor]
  is_map_entry : Bool
  reserved_names : Array[String]
  reserved_ranges : Array[(Int32, Int32)]
  required_numbers : Array[Int32]
  extension_ranges : Array[(Int32, Int32)]
  nested_messages : Array[MessageDescriptor]
  nested_enums : Array[EnumDescriptor]
  nested_extensions : Array[FieldDescriptor]
  file_path : String
  /// The message entry's key and value fields, precomputed for a map entry.
  map_key : FieldDescriptor?
  map_value : FieldDescriptor?
}

///|
/// The field with `number`, or `None`.
pub fn MessageDescriptor::field_by_number(
  self : MessageDescriptor,
  number : Int32,
) -> FieldDescriptor? {
  for field in self.fields {
    if field.number == number {
      return Some(field)
    }
  }
  None
}

///|
/// The field with the proto `name`, or `None`.
pub fn MessageDescriptor::field_by_name(
  self : MessageDescriptor,
  name : String,
) -> FieldDescriptor? {
  for field in self.fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
/// The field whose JSON name is `name`, or `None`.
pub fn MessageDescriptor::field_by_json_name(
  self : MessageDescriptor,
  name : String,
) -> FieldDescriptor? {
  for field in self.fields {
    if field.json_name == name {
      return Some(field)
    }
  }
  None
}

///|
/// The oneof that owns `number`, or `None`.
pub fn MessageDescriptor::oneof_of_field(
  self : MessageDescriptor,
  number : Int32,
) -> OneofDescriptor? {
  for oneof in self.oneofs {
    for field_number in oneof.field_numbers {
      if field_number == number {
        return Some(oneof)
      }
    }
  }
  None
}

///|
/// One method of a service: the messages it takes and returns, and whether
/// either side may send a stream.
pub(all) struct MethodDescriptor {
  name : String
  full_name : String
  input_type : String
  output_type : String
  streaming_client : Bool
  streaming_server : Bool
}

///|
/// A service: the methods it declares, in declaration order.
pub(all) struct ServiceDescriptor {
  name : String
  full_name : String
  methods : Array[MethodDescriptor]
  file_path : String
}

///|
/// One `.proto` file: what it declares, what it imports, and the options written
/// on each declaration. Declarations refer to one another by qualified name
/// rather than by pointer, so a file can be built from the descriptor shape,
/// walked, and converted back without a cycle.
pub(all) struct FileDescriptor {
  path : String
  package_name : String
  syntax : Syntax
  messages : Array[MessageDescriptor]
  enums : Array[EnumDescriptor]
  services : Array[ServiceDescriptor]
  extensions : Array[FieldDescriptor]
  dependencies : Array[String]
  public_dependencies : Array[String]
  /// `edition = "2023"` when the file declares one.
  edition : String?
  /// Options written in the file, keyed by the declared name they belong to;
  /// the file's own options sit under the empty key.
  option_map : Array[(String, Array[(String, String)])]
}

///|
/// The options written on `name` in this file, as (name, value) pairs.
pub fn FileDescriptor::options_of(
  self : FileDescriptor,
  name : String,
) -> Array[(String, String)] {
  for entry in self.option_map {
    if entry.0 == name {
      return entry.1
    }
  }
  []
}

///|
/// The value of one option on `name`, if it was written.
pub fn FileDescriptor::option_of(
  self : FileDescriptor,
  name : String,
  option : String,
) -> String? {
  for pair in self.options_of(name) {
    if pair.0 == option {
      return Some(pair.1)
    }
  }
  None
}

///|
/// The file's own name, without directories.
pub fn FileDescriptor::name(self : FileDescriptor) -> String {
  let path = self.path
  let mut start = 0
  for i in 0..<path.length() {
    if path[i] == '/' {
      start = i + 1
    }
  }
  path[start:].to_owned()
}

///|
/// A qualified name built from a package and a short name.
pub fn qualify(package_name : String, name : String) -> String {
  if package_name.length() == 0 {
    name
  } else {
    package_name + "." + name
  }
}

///|
/// The last segment of a qualified name.
pub fn short_name(full_name : String) -> String {
  let mut start = 0
  for i in 0..<full_name.length() {
    if full_name[i] == '.' {
      start = i + 1
    }
  }
  full_name[start:].to_owned()
}

///|
/// The qualified name with its last segment removed.
pub fn parent_name(full_name : String) -> String {
  let mut last = -1
  for i in 0..<full_name.length() {
    if full_name[i] == '.' {
      last = i
    }
  }
  if last < 0 {
    ""
  } else {
    full_name[:last].to_owned()
  }
}
