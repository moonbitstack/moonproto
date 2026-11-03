// The default list and map implementations. A generated message may use these
// directly; a message type with its own storage may implement the traits
// itself.

///|
/// A list backed by an array. It remembers the element kind so that a new
/// element can be built without consulting the descriptor again.
pub struct ValueList {
  element_kind : Kind
  element_message_type : String?
  items : Array[Value]
}

///|
pub fn ValueList::new(field : FieldDescriptor) -> ValueList {
  {
    element_kind: field.kind,
    element_message_type: field.message_type,
    items: [],
  }
}

///|
pub fn ValueList::from_array(
  field : FieldDescriptor,
  items : Array[Value],
) -> ValueList {
  { element_kind: field.kind, element_message_type: field.message_type, items, }
}

///|
pub impl ListField for ValueList with fn length(self) -> Int32 {
  self.items.length()
}

///|
pub impl ListField for ValueList with fn get(self, index : Int32) -> Value {
  self.items[index]
}

///|
pub impl ListField for ValueList with fn set(self, index : Int32, value : Value) -> Unit {
  self.items[index] = value
}

///|
pub impl ListField for ValueList with fn append(self, value : Value) -> Unit {
  self.items.push(value)
}

///|
pub impl ListField for ValueList with fn append_mutable(self) -> Value {
  let value = new_element_value(self.element_kind, self.element_message_type)
  self.items.push(value)
  value
}

///|
pub impl ListField for ValueList with fn truncate(self, length : Int32) -> Unit {
  if length < self.items.length() {
    self.items.resize(length, Invalid)
  }
}

///|
pub impl ListField for ValueList with fn new_element(self) -> Value {
  new_element_value(self.element_kind, self.element_message_type)
}

///|
pub impl ListField for ValueList with fn is_valid(_self) -> Bool {
  true
}

///|
pub extend ValueList with ListField::{
  length,
  get,
  set,
  append,
  append_mutable,
  truncate,
  new_element,
  is_valid,
}

///|
/// A map backed by an association array. Protobuf maps are usually small, and a
/// linear lookup avoids requiring the key type to be hashable here.
pub struct ValueMap {
  key_kind : Kind
  value_kind : Kind
  value_message_type : String?
  entries : Array[(MapKey, Value)]
}

///|
pub fn ValueMap::new(field : FieldDescriptor) -> ValueMap {
  let key_kind = match field.map_key_field {
    Some(key) => key.kind
    None => String
  }
  let (value_kind, value_message_type) = match field.map_value_field {
    Some(value) => (value.kind, value.message_type)
    None => (String, None)
  }
  { key_kind, value_kind, value_message_type, entries: [], }
}

///|
fn ValueMap::index_of(self : ValueMap, key : MapKey) -> Int32 {
  let mut found = -1
  let mut i = 0
  while i < self.entries.length() {
    if self.entries[i].0 == key {
      found = i
      break
    }
    i = i + 1
  }
  found
}

///|
pub impl MapField for ValueMap with fn length(self) -> Int32 {
  self.entries.length()
}

///|
pub impl MapField for ValueMap with fn range(self, f : (MapKey, Value) -> Bool) -> Unit {
  let mut i = 0
  while i < self.entries.length() {
    let (key, value) = self.entries[i]
    if !f(key, value) {
      break
    }
    i = i + 1
  }
}

///|
pub impl MapField for ValueMap with fn has(self, key : MapKey) -> Bool {
  self.index_of(key) >= 0
}

///|
pub impl MapField for ValueMap with fn clear(self, key : MapKey) -> Unit {
  let index = self.index_of(key)
  if index >= 0 {
    let _ = self.entries.remove(index)
  }
}

///|
pub impl MapField for ValueMap with fn get(self, key : MapKey) -> Value {
  let index = self.index_of(key)
  if index >= 0 {
    self.entries[index].1
  } else {
    Invalid
  }
}

///|
pub impl MapField for ValueMap with fn set(self, key : MapKey, value : Value) -> Unit {
  let index = self.index_of(key)
  if index >= 0 {
    self.entries[index] = (key, value)
  } else {
    self.entries.push((key, value))
  }
}

///|
pub impl MapField for ValueMap with fn mutable(self, key : MapKey) -> Value {
  let index = self.index_of(key)
  if index >= 0 {
    self.entries[index].1
  } else {
    let value = new_element_value(self.value_kind, self.value_message_type)
    self.entries.push((key, value))
    value
  }
}

///|
pub impl MapField for ValueMap with fn new_value(self) -> Value {
  new_element_value(self.value_kind, self.value_message_type)
}

///|
pub impl MapField for ValueMap with fn is_valid(_self) -> Bool {
  true
}

///|
pub extend ValueMap with MapField::{
  length,
  range,
  has,
  clear,
  get,
  set,
  mutable,
  new_value,
  is_valid,
}
