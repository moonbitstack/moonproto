// Emitting one message: a struct with the fields the proto declares, the typed
// accessors over them, and the reflective view the encoders see.
//
// The struct is the storage. `has`, `get`, `set`, `clear` and `mutable` match on
// the field number and read or write the named field, so reaching a value never
// walks a descriptor.

///|
/// The MoonBit type a field is stored in: the scalar as it is, an enum as the
/// generated enum, a message as the generated struct.
fn storage_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  match field.kind {
    Double | Float => "Double"
    Int64 | Sint64 | Sfixed64 => "Int64"
    Uint64 | Fixed64 => "UInt64"
    Int32 | Sint32 | Sfixed32 => "Int32"
    Uint32 | Fixed32 => "UInt32"
    Bool => "Bool"
    String => "String"
    Bytes => "Bytes"
    Enum =>
      match field.enum_type {
        Some(name) => naming.type_name(name)
        None => "Int32"
      }
    Message | Group =>
      match field.message_type {
        Some(name) => naming.type_name(name)
        None => "Int32"
      }
  }
}

///|
/// The storage type of one field: the optional wrapper presence adds, or the
/// container a repeated or map field is held in.
fn slot_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  if field.is_map {
    let key = match field.map_key_field {
      Some(key) => storage_text(key, naming)
      None => "String"
    }
    let value = match field.map_value_field {
      Some(value) => storage_text(value, naming)
      None => "String"
    }
    "Map[" + key + ", " + value + "]"
  } else if field.cardinality == @reflect.Repeated {
    "Array[" + storage_text(field, naming) + "]"
  } else if field.kind.is_message() || field.has_presence {
    storage_text(field, naming) + "?"
  } else {
    storage_text(field, naming)
  }
}

///|
/// A `Value` expression for a storage expression.
fn to_value(field : @reflect.FieldDescriptor, expr : String) -> String {
  match field.kind {
    Double => "@reflect.Double(" + expr + ")"
    Float => "@reflect.float_value(" + expr + ")"
    Int64 | Sint64 | Sfixed64 => "@reflect.Int64(" + expr + ")"
    Uint64 | Fixed64 => "@reflect.Uint64(" + expr + ")"
    Int32 | Sint32 | Sfixed32 => "@reflect.Int32(" + expr + ")"
    Uint32 | Fixed32 => "@reflect.Uint32(" + expr + ")"
    Bool => "@reflect.Bool(" + expr + ")"
    String => "@reflect.String(" + expr + ")"
    Bytes => "@reflect.Bytes(" + expr + ")"
    Enum => "@reflect.Enum(" + expr + ".code())"
    Message | Group => "@reflect.Message(" + expr + " as &@reflect.Message)"
  }
}

///|
/// A storage expression for a `Value` expression.
fn from_value(
  field : @reflect.FieldDescriptor,
  expr : String,
  naming : Naming,
) -> String raise Refused {
  match field.kind {
    Double | Float => expr + ".float()"
    Int64 | Sint64 | Sfixed64 => expr + ".int()"
    Uint64 | Fixed64 => expr + ".uint()"
    Int32 | Sint32 | Sfixed32 => expr + ".int().to_int()"
    Uint32 | Fixed32 => expr + ".uint().to_uint()"
    Bool => expr + ".bool()"
    String => expr + ".string()"
    Bytes => expr + ".bytes()"
    Enum => storage_text(field, naming) + "::of(" + expr + ".enum_number())"
    Message | Group => expr
  }
}

///|
/// The zero of a field's kind as a storage expression.
fn zero_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  match field.kind {
    Double | Float => "0.0"
    Int64 | Sint64 | Sfixed64 => "0L"
    Uint64 | Fixed64 => "0UL"
    Int32 | Sint32 | Sfixed32 => "0"
    Uint32 | Fixed32 => "0U"
    Bool => "false"
    String => "\"\""
    Bytes => "b\"\""
    Enum => storage_text(field, naming) + "::of(0)"
    Message | Group => "None"
  }
}

///|
/// The enum number an absent enum field reads as.
fn enum_default_number(field : @reflect.FieldDescriptor) -> Int32 {
  if field.has_default {
    match field.default_value {
      Enum(number) => return number
      _ => ()
    }
  }
  0
}

///|
/// The value an absent scalar field reads as: the declared default when there is
/// one, the kind's zero otherwise.
fn absent_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  if field.has_default {
    match literal_text(field, naming) {
      Some(text) => return text
      None => ()
    }
  }
  zero_text(field, naming)
}

///|
/// A declared default as a MoonBit literal, or `None` when it has no literal
/// spelling here (an infinity, for one).
fn literal_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String? raise Refused {
  match field.default_value {
    Bool(v) => Some(if v { "true" } else { "false" })
    Int32(v) => Some(v.to_string())
    Int64(v) => Some(v.to_string() + "L")
    Uint32(v) => Some(v.to_string() + "U")
    Uint64(v) => Some(v.to_string() + "UL")
    Double(v) =>
      if v.is_nan() || v.is_inf() {
        None
      } else {
        Some(v.to_string())
      }
    String(v) => Some("\"" + escape(v) + "\"")
    Bytes(v) => Some(bytes_literal(v))
    Enum(v) => Some(storage_text(field, naming) + "::of(" + v.to_string() + ")")
    _ => None
  }
}

///|
fn bytes_literal(value : Bytes) -> String {
  let out = Buffer()
  for i in 0..<value.length() {
    let byte = value[i].to_int()
    out.write_string_utf8("\\x" + hex_digit(byte >> 4) + hex_digit(byte & 0xF))
  }
  "b\"" + utf8_of(out.to_bytes()) + "\""
}

///|
fn hex_digit(value : Int32) -> String {
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  if value >= 0 && value < 16 {
    digits[value]
  } else {
    "0"
  }
}

///|
/// Whether a field is stored in a oneof's enum rather than in a slot of its own.
fn in_oneof(
  field : @reflect.FieldDescriptor,
  message : @reflect.MessageDescriptor,
) -> Bool {
  match field.oneof_index {
    Some(index) =>
      index >= 0 &&
      index < message.oneofs.length() &&
      !message.oneofs[index].synthetic
    None => false
  }
}

///|
fn oneof_index_of(
  field : @reflect.FieldDescriptor,
  message : @reflect.MessageDescriptor,
) -> Int32? {
  match field.oneof_index {
    Some(index) =>
      if index >= 0 && index < message.oneofs.length() {
        Some(index)
      } else {
        None
      }
    None => None
  }
}

///|
/// The variant name of a field inside its oneof's enum.
fn variant_name(
  field : @reflect.FieldDescriptor,
  members : Array[@reflect.FieldDescriptor],
) -> String {
  let taken : Array[String] = []
  for field_of_oneof in members {
    let mut name = upper_first(field_of_oneof.name)
    let mut index = 1
    while taken.contains(name) {
      name = upper_first(field_of_oneof.name) + index.to_string()
      index = index + 1
    }
    if field_of_oneof.number == field.number {
      return name
    }
    taken.push(name)
  }
  upper_first(field.name)
}

///|
fn oneof_type_name(name : String, oneof : @reflect.OneofDescriptor) -> String {
  name + "_" + upper_first(oneof.name)
}

///|
fn oneof_empty_variant(oneof : @reflect.OneofDescriptor) -> String {
  "No" + upper_first(oneof.name)
}

///|
fn members_of(
  message : @reflect.MessageDescriptor,
  oneof : @reflect.OneofDescriptor,
) -> Array[@reflect.FieldDescriptor] {
  let members : Array[@reflect.FieldDescriptor] = []
  for number in oneof.field_numbers {
    match message.field_by_number(number) {
      Some(field) => members.push(field)
      None => ()
    }
  }
  members
}

///|
/// The element of a repeated field or a map value: how one element moves
/// between its typed form and a `Value`.
fn element_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  if field.kind.is_message() {
    let child = storage_text(field, naming)
    "@reflect.message_element(v => @reflect.Message(v as &@reflect.Message), " +
    "() => " +
    child +
    "::new(), (v, m) => @proto.merge(v, m))"
  } else {
    "@reflect.scalar_element(v => " +
    to_value(field, "v") +
    ", v => " +
    from_value(field, "v", naming) +
    ", () => " +
    zero_text(field, naming) +
    ")"
  }
}

///|
/// Emit one message: the struct, its constructor, its accessors, its oneofs and
/// its reflective implementation.
pub fn emit_message(
  message : @reflect.MessageDescriptor,
  prefix : String,
  tag : String,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  let name = type_ident(wrapper_name(prefix, message.name))
  let has_extensions = message.extension_ranges.length() > 0
  let plain : Array[@reflect.FieldDescriptor] = []
  for field in message.fields {
    if !in_oneof(field, message) {
      plain.push(field)
    }
  }
  let oneofs : Array[@reflect.OneofDescriptor] = []
  for oneof in message.oneofs {
    if !oneof.synthetic && oneof.field_numbers.length() > 0 {
      oneofs.push(oneof)
    }
  }
  emit_struct(name, plain, oneofs, has_extensions, naming, buf)
  emit_constructor(name, plain, oneofs, has_extensions, naming, buf)
  emit_accessors(message, name, naming, buf)
  emit_oneof_enums(message, name, oneofs, naming, buf)
  emit_json(name, buf)
  emit_reader(message, name, has_extensions, naming, buf)
  emit_message_impl(message, name, tag, has_extensions, naming, buf)
  emit_message_type(name, tag, buf)
}

///|
fn emit_struct(
  name : String,
  plain : Array[@reflect.FieldDescriptor],
  oneofs : Array[@reflect.OneofDescriptor],
  has_extensions : Bool,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  buf.write_string_utf8("///|\npub struct " + name + " {\n")
  for field in plain {
    // A repeated or map field is mutated through its container, never
    // reassigned, so it is not `mut`.
    let mutable = !(field.is_map || field.cardinality == @reflect.Repeated)
    buf.write_string_utf8(
      "  " +
      (if mutable { "mut " } else { "" }) +
      field_ident(field.name) +
      " : " +
      slot_text(field, naming) +
      "\n",
    )
  }
  for oneof in oneofs {
    buf.write_string_utf8(
      "  mut " +
      field_ident(oneof.name) +
      " : " +
      oneof_type_name(name, oneof) +
      "\n",
    )
  }
  buf.write_string_utf8("  mut unknown_fields : Bytes\n")
  if has_extensions {
    buf.write_string_utf8(
      "  mut extension_values : Array[(@reflect.FieldDescriptor, @reflect.Value)]\n",
    )
  }
  buf.write_string_utf8("}\n\n")
}

///|
fn emit_constructor(
  name : String,
  plain : Array[@reflect.FieldDescriptor],
  oneofs : Array[@reflect.OneofDescriptor],
  has_extensions : Bool,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  buf.write_string_utf8(
    "///|\npub fn " + name + "::new() -> " + name + " {\n  {\n",
  )
  for field in plain {
    buf.write_string_utf8(
      "    " +
      field_ident(field.name) +
      ": " +
      initial_text(field, naming) +
      ",\n",
    )
  }
  for oneof in oneofs {
    buf.write_string_utf8(
      "    " +
      field_ident(oneof.name) +
      ": " +
      oneof_type_name(name, oneof) +
      "::" +
      oneof_empty_variant(oneof) +
      ",\n",
    )
  }
  buf.write_string_utf8("    unknown_fields: b\"\",\n")
  if has_extensions {
    buf.write_string_utf8("    extension_values: [],\n")
  }
  buf.write_string_utf8("  }\n}\n\n")
}

///|
fn initial_text(
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  if field.is_map {
    "Map([])"
  } else if field.cardinality == @reflect.Repeated {
    "[]"
  } else if field.has_presence || field.kind.is_message() {
    "None"
  } else {
    absent_text(field, naming)
  }
}

///|
/// The typed accessors written code uses: one per field, plus the setter for a
/// field that is not a container.
fn emit_accessors(
  message : @reflect.MessageDescriptor,
  name : String,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  for field in message.fields {
    let ident = field_ident(field.name)
    let slot = "self." + ident
    if field.is_map {
      let key = match field.map_key_field {
        Some(key) => key
        None => field
      }
      let value = match field.map_value_field {
        Some(value) => value
        None => field
      }
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        ident +
        "(self : " +
        name +
        ") -> &@reflect.MapField {\n  @reflect.map_view(" +
        slot +
        ", k => " +
        key_value_text(key) +
        ", k => " +
        key_of_text(key) +
        ", " +
        element_text(value, naming) +
        ")\n}\n\n",
      )
      continue
    }
    if field.cardinality == @reflect.Repeated {
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        ident +
        "(self : " +
        name +
        ") -> &@reflect.ListField {\n  @reflect.list_view(" +
        slot +
        ", " +
        element_text(field, naming) +
        ")\n}\n\n",
      )
      continue
    }
    if field.kind.is_message() {
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::" +
        ident +
        "(self : " +
        name +
        ") -> @reflect.Value {\n" +
        message_read_text(name, message, field, naming) +
        "}\n\n",
      )
      buf.write_string_utf8(
        "///|\npub fn " +
        name +
        "::set_" +
        ident +
        "(self : " +
        name +
        ", value : @reflect.Value) -> Unit {\n" +
        message_assign_text(name, message, field, naming) +
        "}\n\n",
      )
      continue
    }
    // A scalar, whether or not it is a field_of_oneof of a oneof.
    let ty = scalar_text(field)
    let read = scalar_read_text(message, field, slot, naming)
    buf.write_string_utf8(
      "///|\npub fn " +
      name +
      "::" +
      ident +
      "(self : " +
      name +
      ") -> " +
      ty +
      " {\n" +
      read +
      "}\n\n",
    )
    let body = if in_oneof(field, message) {
      let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
      let members = members_of(message, oneof)
      "  self." +
      field_ident(oneof.name) +
      " = " +
      oneof_type_name(name, oneof) +
      "::" +
      variant_name(field, members) +
      "(" +
      (if field.kind == @reflect.Enum {
        storage_text(field, naming) + "::of(value)"
      } else {
        "value"
      }) +
      ")\n"
    } else if field.has_presence {
      "  self." +
      ident +
      " = Some(" +
      (if field.kind == @reflect.Enum {
        storage_text(field, naming) + "::of(value)"
      } else {
        "value"
      }) +
      ")\n"
    } else {
      "  self." +
      ident +
      " = " +
      (if field.kind == @reflect.Enum {
        storage_text(field, naming) + "::of(value)"
      } else {
        "value"
      }) +
      "\n"
    }
    buf.write_string_utf8(
      "///|\npub fn " +
      name +
      "::set_" +
      ident +
      "(self : " +
      name +
      ", value : " +
      ty +
      ") -> Unit {\n" +
      body +
      "}\n\n",
    )
  }
}

///|
/// What a scalar accessor reads: the slot itself, the optional wrapper, or the
/// variant of the oneof that holds it.
fn scalar_read_text(
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  slot : String,
  naming : Naming,
) -> String raise Refused {
  if in_oneof(field, message) {
    let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
    let members = members_of(message, oneof)
    let variant = variant_name(field, members)
    let fallback = if field.kind == @reflect.Enum {
      enum_default_number(field).to_string()
    } else {
      absent_text(field, naming)
    }
    let read = if field.kind == @reflect.Enum { "v.code()" } else { "v" }
    "  match self." +
    field_ident(oneof.name) +
    " {\n    " +
    variant +
    "(v) => " +
    read +
    "\n    _ => " +
    fallback +
    "\n  }\n"
  } else if field.has_presence {
    if field.kind == @reflect.Enum {
      "  match " +
      slot +
      " {\n    Some(v) => v.code()\n    None => " +
      enum_default_number(field).to_string() +
      "\n  }\n"
    } else {
      "  " + slot + ".unwrap_or(" + absent_text(field, naming) + ")\n"
    }
  } else if field.kind == @reflect.Enum {
    "  " + slot + ".code()\n"
  } else {
    "  " + slot + "\n"
  }
}

///|
/// The accessor type of a scalar field: an enum reads as its number, as it did
/// before the storage became typed.
fn scalar_text(field : @reflect.FieldDescriptor) -> String {
  match field.kind {
    Double | Float => "Double"
    Int64 | Sint64 | Sfixed64 => "Int64"
    Uint64 | Fixed64 => "UInt64"
    Int32 | Sint32 | Sfixed32 => "Int32"
    Uint32 | Fixed32 => "UInt32"
    Bool => "Bool"
    String => "String"
    Bytes => "Bytes"
    Enum => "Int32"
    Message | Group => "@reflect.Value"
  }
}

///|
fn key_value_text(key : @reflect.FieldDescriptor) -> String {
  match key.kind {
    Bool => "@reflect.Bool(k)"
    Int32 | Sint32 | Sfixed32 => "@reflect.Int32(k)"
    Int64 | Sint64 | Sfixed64 => "@reflect.Int64(k)"
    Uint32 | Fixed32 => "@reflect.Uint32(k)"
    Uint64 | Fixed64 => "@reflect.Uint64(k)"
    _ => "@reflect.String(k)"
  }
}

///|
fn key_of_text(key : @reflect.FieldDescriptor) -> String {
  match key.kind {
    Bool => "k.bool()"
    Int32 | Sint32 | Sfixed32 => "k.int().to_int()"
    Int64 | Sint64 | Sfixed64 => "k.int()"
    Uint32 | Fixed32 => "k.uint().to_uint()"
    Uint64 | Fixed64 => "k.uint()"
    _ => "k.string()"
  }
}

///|
/// The body of a message field's accessor, whether the field owns a slot or
/// lives in a oneof.
fn message_read_text(
  name : String,
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  if in_oneof(field, message) {
    let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
    let variant = variant_name(field, members_of(message, oneof))
    "  match self." +
    field_ident(oneof.name) +
    " {\n    " +
    oneof_type_name(name, oneof) +
    "::" +
    variant +
    "(v) => @reflect.Message(v as &@reflect.Message)\n    _ => @reflect.Message((" +
    storage_text(field, naming) +
    "::new() as &@reflect.Message))\n  }\n"
  } else {
    message_get_text(field, "self." + field_ident(field.name), naming)
  }
}

///|
/// The body that stores a message value into a field, whether the field owns a
/// slot or lives in a oneof. The value is copied, because the concrete type
/// cannot be recovered from a `Value`.
fn message_assign_text(
  name : String,
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  if in_oneof(field, message) {
    let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
    let variant = variant_name(field, members_of(message, oneof))
    "{\n    let source = value.message()\n    let target = " +
    storage_text(field, naming) +
    "::new()\n    @proto.merge(target, source)\n    self." +
    field_ident(oneof.name) +
    " = " +
    oneof_type_name(name, oneof) +
    "::" +
    variant +
    "(target)\n  }\n"
  } else {
    "{\n" +
    message_set_text(field, "self." + field_ident(field.name), naming) +
    "  }\n"
  }
}

///|
/// The body of a message field's accessor: the child, or an empty one.
fn message_get_text(
  field : @reflect.FieldDescriptor,
  slot : String,
  naming : Naming,
) -> String raise Refused {
  "  match " +
  slot +
  " {\n    Some(v) => @reflect.Message(v as &@reflect.Message)\n    None => @reflect.Message((" +
  storage_text(field, naming) +
  "::new() as &@reflect.Message))\n  }\n"
}

///|
/// The body of a message field's setter: the value is copied into a child of the
/// declared type, because the concrete type cannot be recovered from a `Value`.
fn message_set_text(
  field : @reflect.FieldDescriptor,
  slot : String,
  naming : Naming,
) -> String raise Refused {
  "  let source = value.message()\n  let target = " +
  storage_text(field, naming) +
  "::new()\n  @proto.merge(target, source)\n  " +
  slot +
  " = Some(target)\n"
}

///|
fn emit_oneof_enums(
  message : @reflect.MessageDescriptor,
  name : String,
  oneofs : Array[@reflect.OneofDescriptor],
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  for oneof in oneofs {
    let members = members_of(message, oneof)
    let choice = oneof_type_name(name, oneof)
    let empty = oneof_empty_variant(oneof)
    buf.write_string_utf8("///|\npub(all) enum " + choice + " {\n")
    for field in members {
      // A message and an enum keep their own type inside the variant; a
      // scalar takes the accessor type, so an enum reads as its number.
      let payload = if field.kind.is_message() || field.kind == @reflect.Enum {
        storage_text(field, naming)
      } else {
        scalar_text(field)
      }
      buf.write_string_utf8(
        "  " + variant_name(field, members) + "(" + payload + ")\n",
      )
    }
    buf.write_string_utf8("  " + empty + "\n}\n\n")
    let ident = field_ident(oneof.name)
    buf.write_string_utf8(
      "///|\npub fn " +
      name +
      "::" +
      ident +
      "(self : " +
      name +
      ") -> " +
      choice +
      " {\n  self." +
      ident +
      "\n}\n\n",
    )
    buf.write_string_utf8(
      "///|\npub fn " +
      name +
      "::set_" +
      ident +
      "(self : " +
      name +
      ", value : " +
      choice +
      ") -> Unit {\n  self." +
      ident +
      " = value\n}\n\n",
    )
  }
}

///|
fn emit_json(name : String, buf : Buffer) -> Unit {
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
}

///|
/// The reader every other method shares: one match on the field number.
fn emit_reader(
  message : @reflect.MessageDescriptor,
  name : String,
  has_extensions : Bool,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  buf.write_string_utf8(
    "///|\nfn " +
    name +
    "::read_field(self : " +
    name +
    ", field : @reflect.FieldDescriptor) -> @reflect.Value {\n  let _ = self\n  match field.number {\n",
  )
  for field in message.fields {
    let slot = "self." + field_ident(field.name)
    let body = if field.is_map {
      let key = match field.map_key_field {
        Some(key) => key
        None => field
      }
      let value = match field.map_value_field {
        Some(value) => value
        None => field
      }
      "@reflect.MapView(@reflect.map_view(" +
      slot +
      ", k => " +
      key_value_text(key) +
      ", k => " +
      key_of_text(key) +
      ", " +
      element_text(value, naming) +
      "))"
    } else if field.cardinality == @reflect.Repeated {
      "@reflect.ListView(@reflect.list_view(" +
      slot +
      ", " +
      element_text(field, naming) +
      "))"
    } else if in_oneof(field, message) {
      let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
      let variant = variant_name(field, members_of(message, oneof))
      let read = if field.kind.is_message() {
        "@reflect.Message(v as &@reflect.Message)"
      } else {
        to_value(field, "v")
      }
      "match self." +
      field_ident(oneof.name) +
      " {\n      " +
      variant +
      "(v) => " +
      read +
      "\n      _ => @reflect.default_for(field)\n    }"
    } else if field.kind.is_message() {
      "match " +
      slot +
      " {\n      Some(v) => @reflect.Message(v as &@reflect.Message)\n      None => @reflect.Message((" +
      storage_text(field, naming) +
      "::new() as &@reflect.Message))\n    }"
    } else if field.has_presence {
      "match " +
      slot +
      " {\n      Some(v) => " +
      to_value(field, "v") +
      "\n      None => @reflect.default_for(field)\n    }"
    } else {
      to_value(field, slot)
    }
    buf.write_string_utf8(
      "    " + field.number.to_string() + " => " + body + "\n",
    )
  }
  let fallback = if has_extensions {
    "{\n      for pair in self.extension_values {\n        if pair.0.number == field.number {\n          return pair.1\n        }\n      }\n      @reflect.default_for(field)\n    }"
  } else {
    "@reflect.default_for(field)"
  }
  buf.write_string_utf8("    _ => " + fallback + "\n  }\n}\n\n")
}

///|
/// `has` for one field.
fn has_text(
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  let slot = "self." + field_ident(field.name)
  if field.is_map || field.cardinality == @reflect.Repeated {
    slot + ".length() > 0"
  } else if in_oneof(field, message) {
    let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
    let variant = variant_name(field, members_of(message, oneof))
    "match self." +
    field_ident(oneof.name) +
    " {\n      " +
    variant +
    "(_) => true\n      _ => false\n    }"
  } else if field.has_presence || field.kind.is_message() {
    "@reflect.is_set(" + slot + ")"
  } else {
    match field.kind {
      Bool => slot
      String | Bytes => slot + ".length() > 0"
      Double | Float => slot + " != 0.0"
      Enum => slot + ".code() != 0"
      _ => slot + " != " + zero_text(field, naming)
    }
  }
}

///|
/// `clear` for one field.
fn clear_text(
  name : String,
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  let slot = "self." + field_ident(field.name)
  if field.is_map || field.cardinality == @reflect.Repeated {
    slot + ".clear()"
  } else if in_oneof(field, message) {
    let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
    "self." +
    field_ident(oneof.name) +
    " = " +
    oneof_type_name(name, oneof) +
    "::" +
    oneof_empty_variant(oneof)
  } else if field.has_presence || field.kind.is_message() {
    slot + " = None"
  } else {
    slot + " = " + zero_text(field, naming)
  }
}

///|
/// `set` for one field, excluding the extension fallback.
fn set_text(
  name : String,
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  let slot = "self." + field_ident(field.name)
  if field.is_map {
    let key = match field.map_key_field {
      Some(key) => key
      None => field
    }
    let value = match field.map_value_field {
      Some(value) => value
      None => field
    }
    "@reflect.assign_map(" +
    slot +
    ", value.map(), k => " +
    key_of_text(key) +
    ", " +
    element_text(value, naming) +
    ")"
  } else if field.cardinality == @reflect.Repeated {
    "@reflect.assign_list(" +
    slot +
    ", value.list(), " +
    element_text(field, naming) +
    ")"
  } else if field.kind.is_message() {
    message_assign_text(name, message, field, naming)
  } else {
    let typed = from_value(field, "value", naming)
    if in_oneof(field, message) {
      let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
      let variant = variant_name(field, members_of(message, oneof))
      "self." +
      field_ident(oneof.name) +
      " = " +
      oneof_type_name(name, oneof) +
      "::" +
      variant +
      "(" +
      typed +
      ")"
    } else if field.has_presence {
      slot + " = Some(" + typed + ")"
    } else {
      slot + " = " + typed
    }
  }
}

///|
/// `mutable` for one field: a message child is created in place, everything else
/// is its own view.
fn mutable_text(
  name : String,
  message : @reflect.MessageDescriptor,
  field : @reflect.FieldDescriptor,
  naming : Naming,
) -> String raise Refused {
  let slot = "self." + field_ident(field.name)
  if field.kind.is_message() && in_oneof(field, message) {
    let oneof = message.oneofs[oneof_index_of(field, message).unwrap()]
    let variant = variant_name(field, members_of(message, oneof))
    let choice = oneof_type_name(name, oneof)
    "match self." +
    field_ident(oneof.name) +
    " {\n      " +
    variant +
    "(v) => @reflect.Message(v as &@reflect.Message)\n      _ => {\n        let v = " +
    storage_text(field, naming) +
    "::new()\n        self." +
    field_ident(oneof.name) +
    " = " +
    choice +
    "::" +
    variant +
    "(v)\n        @reflect.Message(v as &@reflect.Message)\n      }\n    }"
  } else {
    "match " +
    slot +
    " {\n      Some(v) => @reflect.Message(v as &@reflect.Message)\n      None => {\n        let v = " +
    storage_text(field, naming) +
    "::new()\n        " +
    slot +
    " = Some(v)\n        @reflect.Message(v as &@reflect.Message)\n      }\n    }"
  }
}

///|
/// Emit the `Message` implementation: every method over the struct's own fields.
fn emit_message_impl(
  message : @reflect.MessageDescriptor,
  name : String,
  tag : String,
  has_extensions : Bool,
  naming : Naming,
  buf : Buffer,
) -> Unit raise Refused {
  buf.write_string_utf8(
    "///|\nlet " +
    descriptor_ident(tag, name) +
    " : @reflect.MessageDescriptor = find_message_" +
    tag +
    "(\"" +
    escape(message.full_name) +
    "\")\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn descriptor(self) -> @reflect.MessageDescriptor {\n  let _ = self\n  " +
    descriptor_ident(tag, name) +
    "\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn message_type(self) -> &@reflect.MessageType {\n  let _ = self\n  " +
    lower_name(name) +
    "_type\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn is_valid(self) -> Bool {\n  let _ = self\n  true\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn range(self, f : (@reflect.FieldDescriptor, @reflect.Value) -> Bool) -> Unit {\n  for field in " +
    descriptor_ident(tag, name) +
    ".fields {\n    if @reflect.Message::has(self, field) {\n      if !f(field, @reflect.Message::get(self, field)) {\n        break\n      }\n    }\n  }\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn range_extensions(self, f : (@reflect.FieldDescriptor, @reflect.Value) -> Bool) -> Unit {\n",
  )
  if has_extensions {
    buf.write_string_utf8(
      "  for pair in self.extension_values {\n    if !f(pair.0, pair.1) {\n      break\n    }\n  }\n",
    )
  } else {
    buf.write_string_utf8("  let _ = self\n  let _ = f\n")
  }
  buf.write_string_utf8("}\n\n")
  // has
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn has(self, field : @reflect.FieldDescriptor) -> Bool {\n  let _ = self\n  match field.number {\n",
  )
  for field in message.fields {
    buf.write_string_utf8(
      "    " +
      field.number.to_string() +
      " => " +
      has_text(message, field, naming) +
      "\n",
    )
  }
  buf.write_string_utf8(
    "    _ => " + extension_has_text(has_extensions) + "\n  }\n}\n\n",
  )
  // clear
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn clear(self, field : @reflect.FieldDescriptor) -> Unit {\n  let _ = self\n  match field.number {\n",
  )
  for field in message.fields {
    buf.write_string_utf8(
      "    " +
      field.number.to_string() +
      " => " +
      clear_text(name, message, field, naming) +
      "\n",
    )
  }
  buf.write_string_utf8(
    "    _ => " + extension_clear_text(has_extensions) + "\n  }\n}\n\n",
  )
  // get
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn get(self, field : @reflect.FieldDescriptor) -> @reflect.Value {\n  " +
    name +
    "::read_field(self, field)\n}\n\n",
  )
  // set
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn set(self, field : @reflect.FieldDescriptor, value : @reflect.Value) -> Unit {\n  let _ = self\n  let _ = value\n  match field.number {\n",
  )
  for field in message.fields {
    buf.write_string_utf8(
      "    " +
      field.number.to_string() +
      " => " +
      set_text(name, message, field, naming) +
      "\n",
    )
  }
  buf.write_string_utf8(
    "    _ => " + extension_set_text(has_extensions) + "\n  }\n}\n\n",
  )
  // mutable
  let message_fields : Array[@reflect.FieldDescriptor] = []
  for field in message.fields {
    if field.kind.is_message() &&
      !field.is_map &&
      field.cardinality != @reflect.Repeated {
      message_fields.push(field)
    }
  }
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn mutable(self, field : @reflect.FieldDescriptor) -> @reflect.Value {\n  let _ = self\n  match field.number {\n",
  )
  for field in message_fields {
    buf.write_string_utf8(
      "    " +
      field.number.to_string() +
      " => " +
      mutable_text(name, message, field, naming) +
      "\n",
    )
  }
  if has_extensions {
    // An extension is reached through `mutable` when a decoder meets a message
    // body for it; the value has to be registered the way `set` does, or
    // `range_extensions` never sees it.
    buf.write_string_utf8(
      "    _ => {\n      if field.is_extension && !self.has(field) {\n        let value = @reflect.new_field_value(field)\n        self.set(field, value)\n        value\n      } else {\n        " +
      name +
      "::read_field(self, field)\n      }\n    }\n  }\n}\n\n",
    )
  } else {
    buf.write_string_utf8(
      "    _ => " + name + "::read_field(self, field)\n  }\n}\n\n",
    )
  }
  // new_field
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn new_field(self, field : @reflect.FieldDescriptor) -> @reflect.Value {\n  let _ = self\n  match field.number {\n",
  )
  for field in message_fields {
    buf.write_string_utf8(
      "    " +
      field.number.to_string() +
      " => @reflect.Message((" +
      storage_text(field, naming) +
      "::new() as &@reflect.Message))\n",
    )
  }
  buf.write_string_utf8("    _ => @reflect.new_field_value(field)\n  }\n}\n\n")
  // which_oneof
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn which_oneof(self, oneof : @reflect.OneofDescriptor) -> Int32? {\n  let _ = self\n  match oneof.name {\n",
  )
  for oneof in message.oneofs {
    let members = members_of(message, oneof)
    if members.length() == 0 {
      continue
    }
    buf.write_string_utf8(
      "    \"" +
      escape(oneof.name) +
      "\" => " +
      which_oneof_text(name, message, oneof) +
      "\n",
    )
  }
  buf.write_string_utf8("    _ => None\n  }\n}\n\n")
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn get_unknown(self) -> @reflect.RawFields {\n  @reflect.RawFields::from_bytes(self.unknown_fields)\n}\n\n",
  )
  buf.write_string_utf8(
    "///|\npub impl @reflect.Message for " +
    name +
    " with fn set_unknown(self, raw : @reflect.RawFields) -> Unit {\n  self.unknown_fields = raw.bytes()\n}\n\n",
  )
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
}

///|
fn descriptor_ident(tag : String, name : String) -> String {
  "descriptor_" + tag + "_" + name
}

///|
fn extension_has_text(has_extensions : Bool) -> String {
  if has_extensions {
    "{\n      for pair in self.extension_values {\n        if pair.0.number == field.number {\n          return true\n        }\n      }\n      false\n    }"
  } else {
    "false"
  }
}

///|
fn extension_clear_text(has_extensions : Bool) -> String {
  if has_extensions {
    "{\n      let kept : Array[(@reflect.FieldDescriptor, @reflect.Value)] = []\n      for pair in self.extension_values {\n        if pair.0.number != field.number {\n          kept.push(pair)\n        }\n      }\n      self.extension_values = kept\n    }"
  } else {
    "()"
  }
}

///|
fn extension_set_text(has_extensions : Bool) -> String {
  if has_extensions {
    "{\n      let mut found = false\n      for i in 0..<self.extension_values.length() {\n        if self.extension_values[i].0.number == field.number {\n          self.extension_values[i] = (field, value)\n          found = true\n        }\n      }\n      if !found {\n        self.extension_values.push((field, value))\n      }\n    }"
  } else {
    "()"
  }
}

///|
fn which_oneof_text(
  name : String,
  message : @reflect.MessageDescriptor,
  oneof : @reflect.OneofDescriptor,
) -> String {
  let members = members_of(message, oneof)
  if oneof.synthetic {
    let field = members[0]
    return "if @reflect.is_set(self." +
      field_ident(field.name) +
      ") { Some(" +
      field.number.to_string() +
      ") } else { None }"
  }
  let mut out = "match self." + field_ident(oneof.name) + " {\n"
  for field in members {
    out = out +
      "      " +
      oneof_type_name(name, oneof) +
      "::" +
      variant_name(field, members) +
      "(_) => Some(" +
      field.number.to_string() +
      ")\n"
  }
  out + "      _ => None\n    }"
}

///|
/// Emit the type record: one per message, so an `Any` or a `New` can find the
/// constructor by name.
fn emit_message_type(name : String, tag : String, buf : Buffer) -> Unit {
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
    "Type with fn descriptor(_self) -> @reflect.MessageDescriptor {\n  " +
    descriptor_ident(tag, name) +
    "\n}\n\n",
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
