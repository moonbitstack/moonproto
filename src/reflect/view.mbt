// Typed views over the arrays and maps a generated message stores its fields
// in. The reflective contract speaks `Value`, `MapKey` and `ListField`; a
// generated message keeps `Array[Int32]` and `Map[String, Child]`. These are
// the two places the two meet, and the only code that knows how an element
// moves between them.

///|
/// How to move one element of a repeated or map field between its typed form
/// and a `Value`. `copy_into` exists because a message element cannot be
/// reconstructed from a `Value`: the concrete type is only known here, so the
/// value is copied into storage instead.
pub(all) struct Element[T] {
  to_value : (T) -> Value
  from_value : (Value) -> T
  make : () -> T
  copy_into : (T, &Message) -> Unit
  is_message : Bool
}

///|
pub fn[T] Element::new(
  to_value : (T) -> Value,
  from_value : (Value) -> T,
  make : () -> T,
  copy_into : (T, &Message) -> Unit,
  is_message : Bool,
) -> Element[T] {
  { to_value, from_value, make, copy_into, is_message, }
}

///|
/// The element of a repeated field: a scalar converts both ways.
pub fn[T] scalar_element(
  to_value : (T) -> Value,
  from_value : (Value) -> T,
  make : () -> T,
) -> Element[T] {
  Element::new(to_value, from_value, make, fn(_item, _source) { () }, false)
}

///|
/// The element of a repeated message field: a new element is the concrete type,
/// and a value is copied into it.
pub fn[T] message_element(
  to_value : (T) -> Value,
  make : () -> T,
  copy_into : (T, &Message) -> Unit,
) -> Element[T] {
  Element::new(
    to_value,
    fn(_value) { abort("a message element cannot be built from a value") },
    make,
    copy_into,
    true,
  )
}

///|
/// A repeated field backed by the array the message stores.
pub struct TypedList[T] {
  items : Array[T]
  element : Element[T]
}

///|
pub impl[T] ListField for TypedList[T] with fn length(self) -> Int32 {
  self.items.length()
}

///|
pub impl[T] ListField for TypedList[T] with fn get(self, index : Int32) -> Value {
  (self.element.to_value)(self.items[index])
}

///|
pub impl[T] ListField for TypedList[T] with fn set(
  self,
  index : Int32,
  value : Value,
) -> Unit {
  if self.element.is_message {
    (self.element.copy_into)(self.items[index], value.message())
  } else {
    self.items[index] = (self.element.from_value)(value)
  }
}

///|
pub impl[T] ListField for TypedList[T] with fn append(self, value : Value) -> Unit {
  if self.element.is_message {
    let item = (self.element.make)()
    (self.element.copy_into)(item, value.message())
    self.items.push(item)
  } else {
    self.items.push((self.element.from_value)(value))
  }
}

///|
pub impl[T] ListField for TypedList[T] with fn append_mutable(self) -> Value {
  let item = (self.element.make)()
  self.items.push(item)
  (self.element.to_value)(item)
}

///|
pub impl[T] ListField for TypedList[T] with fn truncate(self, length : Int32) -> Unit {
  if length < self.items.length() {
    self.items.resize(length, (self.element.make)())
  }
}

///|
pub impl[T] ListField for TypedList[T] with fn new_element(self) -> Value {
  (self.element.to_value)((self.element.make)())
}

///|
pub impl[T] ListField for TypedList[T] with fn is_valid(_self) -> Bool {
  true
}

///|
pub extend TypedList with ListField::{
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
/// The view a generated message returns for a repeated field.
pub fn[T] list_view(items : Array[T], element : Element[T]) -> &ListField {
  TypedList::{ items, element, }
}

///|
/// Replace the contents of `target` with the elements of `source`.
pub fn[T] assign_list(
  target : Array[T],
  source : &ListField,
  element : Element[T],
) -> Unit {
  target.clear()
  for i in 0..<source.length() {
    if element.is_message {
      let item = (element.make)()
      (element.copy_into)(item, source.get(i).message())
      target.push(item)
    } else {
      target.push((element.from_value)(source.get(i)))
    }
  }
}

///|
/// A map field backed by the map the message stores.
pub struct TypedMap[K, V] {
  entries : Map[K, V]
  key_value : (K) -> MapKey
  key_of : (MapKey) -> K
  element : Element[V]
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn length(self) -> Int32 {
  self.entries.length()
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn range(
  self,
  f : (MapKey, Value) -> Bool,
) -> Unit {
  let mut keep_going = true
  self.entries.each(fn(key, value) {
    if keep_going && !f((self.key_value)(key), (self.element.to_value)(value)) {
      keep_going = false
    }
  })
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn has(
  self,
  key : MapKey,
) -> Bool {
  self.entries.contains((self.key_of)(key))
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn clear(
  self,
  key : MapKey,
) -> Unit {
  self.entries.remove((self.key_of)(key))
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn get(
  self,
  key : MapKey,
) -> Value {
  match self.entries.get((self.key_of)(key)) {
    Some(value) => (self.element.to_value)(value)
    None => Invalid
  }
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn set(
  self,
  key : MapKey,
  value : Value,
) -> Unit {
  let typed = (self.key_of)(key)
  if self.element.is_message {
    match self.entries.get(typed) {
      Some(existing) => (self.element.copy_into)(existing, value.message())
      None => {
        let item = (self.element.make)()
        (self.element.copy_into)(item, value.message())
        self.entries.set(typed, item)
      }
    }
  } else {
    self.entries.set(typed, (self.element.from_value)(value))
  }
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn mutable(
  self,
  key : MapKey,
) -> Value {
  let typed = (self.key_of)(key)
  match self.entries.get(typed) {
    Some(existing) => (self.element.to_value)(existing)
    None => {
      let item = (self.element.make)()
      self.entries.set(typed, item)
      (self.element.to_value)(item)
    }
  }
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn new_value(self) -> Value {
  (self.element.to_value)((self.element.make)())
}

///|
pub impl[K : Hash + Eq, V] MapField for TypedMap[K, V] with fn is_valid(_self) -> Bool {
  true
}

///|
pub extend TypedMap with MapField::{
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

///|
/// The view a generated message returns for a map field.
pub fn[K : Hash + Eq, V] map_view(
  entries : Map[K, V],
  key_value : (K) -> MapKey,
  key_of : (MapKey) -> K,
  element : Element[V],
) -> &MapField {
  TypedMap::{ entries, key_value, key_of, element, }
}

///|
/// Replace the contents of `target` with the entries of `source`.
pub fn[K : Hash + Eq, V] assign_map(
  target : Map[K, V],
  source : &MapField,
  key_of : (MapKey) -> K,
  element : Element[V],
) -> Unit {
  target.clear()
  source.range(fn(key, value) {
    let typed = key_of(key)
    if element.is_message {
      let item = (element.make)()
      (element.copy_into)(item, value.message())
      target.set(typed, item)
    } else {
      target.set(typed, (element.from_value)(value))
    }
    true
  })
}
