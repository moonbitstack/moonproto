// The reflective contract every message, enum, list and map implements. The
// encoders and the generator share these traits; nothing here knows a field's
// storage layout.
//
// `Message` and `MessageType` must stay object-safe: a `Value` holds `&Message`,
// so no method on `Message` may return `Self`. The one constructor that does
// return the concrete type lives on `Fresh`, which is used only in generics.

///|
/// A repeated field: zero-indexed and ordered, with a mutable element for the
/// decoder to fill in place.
///
/// Core already owns the names `List` and `Map`, so the views carry a suffix. A
/// generated message hands its own `Array` to `TypedList` instead of copying it
/// into a container of the library's own, and `ValueList` is the implementation
/// a message keeps when its values are only known at run time.
pub(open) trait ListField {
  fn length(Self) -> Int32
  fn get(Self, Int32) -> Value
  fn set(Self, Int32, Value) -> Unit
  fn append(Self, Value) -> Unit
  fn append_mutable(Self) -> Value
  fn truncate(Self, Int32) -> Unit
  fn new_element(Self) -> Value
  fn is_valid(Self) -> Bool
}

///|
/// A map field: unordered, keyed by one of the six key kinds, with a mutable
/// value for the decoder to fill in place. `TypedMap` wraps a `Map[K, V]` the
/// generated message already has; `ValueMap` is the run-time implementation.
pub(open) trait MapField {
  fn length(Self) -> Int32
  fn range(Self, (MapKey, Value) -> Bool) -> Unit
  fn has(Self, MapKey) -> Bool
  fn clear(Self, MapKey) -> Unit
  fn get(Self, MapKey) -> Value
  fn set(Self, MapKey, Value) -> Unit
  fn mutable(Self, MapKey) -> Value
  fn new_value(Self) -> Value
  fn is_valid(Self) -> Bool
}

///|
/// A concrete enum value.
pub(open) trait Enum {
  fn descriptor(Self) -> EnumDescriptor
  fn enum_type(Self) -> &EnumType
  fn number(Self) -> Int32
}

///|
/// An enum's concrete type: its descriptor and a constructor.
pub(open) trait EnumType {
  fn new_enum(Self, Int32) -> &Enum
  fn descriptor(Self) -> EnumDescriptor
}

///|
/// A message instance, reachable only through its descriptor.
///
/// `has` answers whether a field carries a value. A repeated or map field
/// carries one when it is non-empty, a field with presence when it is set, and
/// a field without presence when its value is not the zero of its kind —
/// writing a zero is the same as leaving the field out. Encoders ask
/// `is_populated`, which is the same rule stated once for every implementation.
pub(open) trait Message {
  fn descriptor(Self) -> MessageDescriptor
  fn message_type(Self) -> &MessageType
  fn is_valid(Self) -> Bool
  fn range(Self, (FieldDescriptor, Value) -> Bool) -> Unit
  fn range_extensions(Self, (FieldDescriptor, Value) -> Bool) -> Unit
  fn has(Self, FieldDescriptor) -> Bool
  fn clear(Self, FieldDescriptor) -> Unit
  fn get(Self, FieldDescriptor) -> Value
  fn set(Self, FieldDescriptor, Value) -> Unit
  fn mutable(Self, FieldDescriptor) -> Value
  fn new_field(Self, FieldDescriptor) -> Value
  fn which_oneof(Self, OneofDescriptor) -> Int32?
  fn get_unknown(Self) -> RawFields
  fn set_unknown(Self, RawFields) -> Unit
}

///|
/// A message's concrete type: its descriptor, and a constructor for an empty
/// instance. The registry stores these, which is how `Any` turns a type URL into
/// a message and how a decoder builds a nested message it has never seen.
pub(open) trait MessageType {
  fn new_message(Self) -> &Message
  fn zero(Self) -> &Message
  fn descriptor(Self) -> MessageDescriptor
}

///|
/// A concrete extension: its descriptor, a value of its kind, and validation of a
/// value assigned to it. There is no conversion to and from a universal carrier,
/// because a value assigned to an extension is already a `Value`; validation is
/// the only thing the two directions had left to do.
pub(open) trait ExtensionType {
  fn new_value(Self) -> Value
  fn zero(Self) -> Value
  fn descriptor(Self) -> FieldDescriptor
  fn is_valid_value(Self, Value) -> Bool
}

///|
/// A message type that can build an empty instance of its own concrete type.
/// Kept apart from `Message` so that `&Message` stays a usable trait object.
pub(open) trait Fresh {
  fn fresh(Self) -> Self
}

///|
/// The zero value for a scalar kind; `Invalid` for a message or group, which
/// has no scalar zero.
pub fn zero_value(kind : Kind) -> Value {
  match kind {
    Bool => Bool(false)
    Int32 | Sint32 | Sfixed32 => Int32(0)
    Int64 | Sint64 | Sfixed64 => Int64(0L)
    Uint32 | Fixed32 => Uint32(0U)
    Uint64 | Fixed64 => Uint64(0UL)
    Float => Float(@float.Float::from_double(0.0))
    Double => Double(0.0)
    String => String("")
    Bytes => Bytes(b"")
    Enum => Enum(0)
    Message | Group => Invalid
  }
}

///|
/// The value `get` returns for a field that is unset: the declared default when
/// there is one, the kind's zero otherwise.
pub fn default_for(field : FieldDescriptor) -> Value {
  if field.has_default {
    field.default_value
  } else {
    zero_value(field.kind)
  }
}

///|
/// A fresh, mutable value assignable to `field`: an empty list, an empty map, a
/// new message, or the scalar default.
pub fn new_field_value(field : FieldDescriptor) -> Value {
  if field.is_map {
    MapView(ValueMap::new(field))
  } else if field.cardinality == Repeated {
    ListView(ValueList::new(field))
  } else if field.kind.is_message() {
    match field.message_type {
      Some(name) =>
        match global_types.find_message_by_name(name) {
          Some(mt) => Message(mt.new_message())
          None => Invalid
        }
      None => Invalid
    }
  } else {
    default_for(field)
  }
}

///|
/// A fresh value for an element of a list or map.
pub fn new_element_value(kind : Kind, message_type : String?) -> Value {
  if kind.is_message() {
    match message_type {
      Some(name) =>
        match global_types.find_message_by_name(name) {
          Some(mt) => Message(mt.new_message())
          None => Invalid
        }
      None => Invalid
    }
  } else {
    zero_value(kind)
  }
}

///|
/// Whether `message` carries a value for `field`, which is what every encoder
/// asks before it writes one. A repeated or map field carries one when it is
/// non-empty; a field with presence when it is set; and a field without
/// presence when its value is not zero, because the wire cannot tell a zero
/// written by hand from a field that was never mentioned.
pub fn is_populated(message : &Message, field : FieldDescriptor) -> Bool {
  if field.is_map || field.is_list() {
    message.has(field)
  } else if field.kind.is_message() || field.has_presence || field.is_extension {
    message.has(field)
  } else {
    !message.get(field).is_zero()
  }
}

///|
/// The dotted path of the first required field that has no value, or `None`
/// when the message and its nested messages are complete. The encoders use
/// this so each can report the omission in its own error type.
pub fn missing_required(message : &Message) -> String? {
  missing_required_at(message, "")
}

///|
fn missing_required_at(message : &Message, prefix : String) -> String? {
  let desc = message.descriptor()
  for number in desc.required_numbers {
    match desc.field_by_number(number) {
      Some(field) =>
        if !message.has(field) {
          return Some(join_path(prefix, field.name))
        }
      None => ()
    }
  }
  for field in desc.fields {
    if field.kind.is_message() &&
      !field.is_map &&
      !field.is_list() &&
      message.has(field) {
      match
        missing_required_at(
          message.get(field).message(),
          join_path(prefix, field.name),
        ) {
        Some(path) => return Some(path)
        None => ()
      }
    }
  }
  None
}

///|
fn join_path(prefix : String, name : String) -> String {
  if prefix.length() == 0 {
    name
  } else {
    prefix + "." + name
  }
}
