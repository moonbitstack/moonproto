// A message backed by an association array keyed by field number.

///|
pub struct Message {
  desc : @reflect.MessageDescriptor
  msg_type : &@reflect.MessageType
  fields : Array[(Int32, @reflect.Value)]
  mut unknown : Bytes
}

///|
pub fn Message::new(desc : @reflect.MessageDescriptor) -> Message {
  let mt = MessageType::new(desc)
  { desc, msg_type: mt as &@reflect.MessageType, fields: [], unknown: b"", }
}

///|
pub fn Message::new_with_type(
  desc : @reflect.MessageDescriptor,
  msg_type : &@reflect.MessageType,
) -> Message {
  { desc, msg_type, fields: [], unknown: b"", }
}

///|
fn Message::index_of(self : Message, number : Int32) -> Int32 {
  let mut found = -1
  let mut i = 0
  while i < self.fields.length() {
    if self.fields[i].0 == number {
      found = i
      break
    }
    i = i + 1
  }
  found
}

///|
fn Message::remove_field(self : Message, number : Int32) -> Unit {
  let index = self.index_of(number)
  if index >= 0 {
    let _ = self.fields.remove(index)
  }
}

///|
fn Message::put_field(
  self : Message,
  number : Int32,
  value : @reflect.Value,
) -> Unit {
  let index = self.index_of(number)
  if index >= 0 {
    self.fields[index] = (number, value)
  } else {
    self.fields.push((number, value))
  }
}

///|
pub impl @reflect.Message for Message with fn descriptor(self) -> @reflect.MessageDescriptor {
  self.desc
}

///|
pub impl @reflect.Message for Message with fn message_type(self) -> &@reflect.MessageType {
  self.msg_type
}

///|
pub impl @reflect.Message for Message with fn is_valid(_self) -> Bool {
  true
}

///|
pub impl @reflect.Message for Message with fn range(
  self,
  f : (@reflect.FieldDescriptor, @reflect.Value) -> Bool,
) -> Unit {
  let mut i = 0
  while i < self.fields.length() {
    let (number, value) = self.fields[i]
    match self.desc.field_by_number(number) {
      Some(field) => if !f(field, value) { break }
      None => ()
    }
    i = i + 1
  }
}

///|
pub impl @reflect.Message for Message with fn has(
  self,
  field : @reflect.FieldDescriptor,
) -> Bool {
  let index = self.index_of(field.number)
  if index < 0 {
    return false
  }
  let value = self.fields[index].1
  if field.is_map {
    value.map().length() > 0
  } else if field.is_list() {
    value.list().length() > 0
  } else {
    true
  }
}

///|
pub impl @reflect.Message for Message with fn clear(
  self,
  field : @reflect.FieldDescriptor,
) -> Unit {
  self.remove_field(field.number)
}

///|
pub impl @reflect.Message for Message with fn get(
  self,
  field : @reflect.FieldDescriptor,
) -> @reflect.Value {
  let index = self.index_of(field.number)
  if index >= 0 {
    self.fields[index].1
  } else {
    @reflect.default_for(field)
  }
}

///|
pub impl @reflect.Message for Message with fn set(
  self,
  field : @reflect.FieldDescriptor,
  value : @reflect.Value,
) -> Unit {
  match field.oneof_index {
    Some(index) =>
      if index >= 0 && index < self.desc.oneofs.length() {
        for number in self.desc.oneofs[index].field_numbers {
          self.remove_field(number)
        }
      }
    None => ()
  }
  self.put_field(field.number, value)
}

///|
pub impl @reflect.Message for Message with fn mutable(
  self,
  field : @reflect.FieldDescriptor,
) -> @reflect.Value {
  let index = self.index_of(field.number)
  if index >= 0 {
    return self.fields[index].1
  }
  let value = @reflect.new_field_value(field)
  self.put_field(field.number, value)
  value
}

///|
pub impl @reflect.Message for Message with fn new_field(
  _self,
  field : @reflect.FieldDescriptor,
) -> @reflect.Value {
  @reflect.new_field_value(field)
}

///|
pub impl @reflect.Message for Message with fn which_oneof(
  self,
  oneof : @reflect.OneofDescriptor,
) -> Int32? {
  for number in oneof.field_numbers {
    if self.index_of(number) >= 0 {
      return Some(number)
    }
  }
  None
}

///|
pub impl @reflect.Message for Message with fn get_unknown(self) -> @reflect.RawFields {
  @reflect.RawFields::from_bytes(self.unknown)
}

///|
pub impl @reflect.Message for Message with fn set_unknown(
  self,
  raw : @reflect.RawFields,
) -> Unit {
  self.unknown = raw.bytes()
}

///|
pub impl @reflect.Fresh for Message with fn fresh(self) -> Message {
  Message::new_with_type(self.desc, self.msg_type)
}

///|
pub extend Message with @reflect.Message::{
  descriptor,
  message_type,
  is_valid,
  range,
  has,
  clear,
  get,
  set,
  mutable,
  new_field,
  which_oneof,
  get_unknown,
  set_unknown,
}

///|
pub extend Message with @reflect.Fresh::{fresh}

///|
/// The type of a dynamic message: its descriptor and a constructor.
pub struct MessageType {
  desc : @reflect.MessageDescriptor
}

///|
pub fn MessageType::new(desc : @reflect.MessageDescriptor) -> MessageType {
  { desc, }
}

///|
pub impl @reflect.MessageType for MessageType with fn new_message(self) -> &@reflect.Message {
  Message::new_with_type(self.desc, self as &@reflect.MessageType)
  as &@reflect.Message
}

///|
pub impl @reflect.MessageType for MessageType with fn zero(self) -> &@reflect.Message {
  Message::new_with_type(self.desc, self as &@reflect.MessageType)
  as &@reflect.Message
}

///|
pub impl @reflect.MessageType for MessageType with fn descriptor(self) -> @reflect.MessageDescriptor {
  self.desc
}

///|
pub fn new_message_type(
  desc : @reflect.MessageDescriptor,
) -> &@reflect.MessageType {
  MessageType::new(desc) as &@reflect.MessageType
}

///|
pub extend MessageType with @reflect.MessageType::{
  new_message,
  zero,
  descriptor,
}

///|
/// An enum value carrying its descriptor and number.
pub struct EnumValue {
  desc : @reflect.EnumDescriptor
  enum_type : &@reflect.EnumType
  number_value : Int32
}

///|
pub impl @reflect.Enum for EnumValue with fn descriptor(self) -> @reflect.EnumDescriptor {
  self.desc
}

///|
pub impl @reflect.Enum for EnumValue with fn enum_type(self) -> &@reflect.EnumType {
  self.enum_type
}

///|
pub impl @reflect.Enum for EnumValue with fn number(self) -> Int32 {
  self.number_value
}

///|
pub extend EnumValue with @reflect.Enum::{descriptor, enum_type, number}

///|
pub struct EnumType {
  desc : @reflect.EnumDescriptor
}

///|
pub fn EnumType::new(desc : @reflect.EnumDescriptor) -> EnumType {
  { desc, }
}

///|
pub impl @reflect.EnumType for EnumType with fn new_enum(self, number : Int32) -> &@reflect.Enum {
  {
    desc: self.desc,
    enum_type: self as &@reflect.EnumType,
    number_value: number,
  }
  as &@reflect.Enum
}

///|
pub impl @reflect.EnumType for EnumType with fn descriptor(self) -> @reflect.EnumDescriptor {
  self.desc
}

///|
pub extend EnumType with @reflect.EnumType::{new_enum, descriptor}

///|
pub fn new_enum_type(desc : @reflect.EnumDescriptor) -> &@reflect.EnumType {
  EnumType::new(desc) as &@reflect.EnumType
}

///|
/// An extension type backed by its descriptor.
pub struct ExtensionType {
  desc : @reflect.FieldDescriptor
}

///|
pub extend ExtensionType with @reflect.ExtensionType::{
  new_value,
  zero,
  descriptor,
  is_valid_value,
}

///|
pub impl @reflect.ExtensionType for ExtensionType with fn new_value(self) -> @reflect.Value {
  @reflect.new_field_value(self.desc)
}

///|
pub impl @reflect.ExtensionType for ExtensionType with fn zero(self) -> @reflect.Value {
  @reflect.zero_value(self.desc.kind)
}

///|
pub impl @reflect.ExtensionType for ExtensionType with fn descriptor(self) -> @reflect.FieldDescriptor {
  self.desc
}

///|
pub impl @reflect.ExtensionType for ExtensionType with fn is_valid_value(
  _self,
  value : @reflect.Value,
) -> Bool {
  value.is_valid()
}

///|
pub fn new_extension_type(
  desc : @reflect.FieldDescriptor,
) -> &@reflect.ExtensionType {
  let value : ExtensionType = { desc, }
  value as &@reflect.ExtensionType
}
