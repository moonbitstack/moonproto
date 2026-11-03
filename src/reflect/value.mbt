// The protobuf data model: the field kinds, the value union, and the raw bytes
// of unknown fields. https://protobuf.dev/programming-guides/proto3/

// The language version a file declares.

///|
#derive(Eq)
pub(all) enum Syntax {
  Proto2
  Proto3
  Editions
}

///|
pub extend Syntax with Eq::{equal, not_equal}

///|
pub fn Syntax::code(self : Syntax) -> Int32 {
  match self {
    Proto2 => 2
    Proto3 => 3
    Editions => 4
  }
}

///|
pub fn Syntax::of(code : Int32) -> Syntax? {
  match code {
    2 => Some(Proto2)
    3 => Some(Proto3)
    4 => Some(Editions)
    _ => None
  }
}

///|
/// Whether a field appears zero or one times, exactly once, or any number of
/// times.
#derive(Eq)
pub(all) enum Cardinality {
  Optional
  Required
  Repeated
}

///|
pub extend Cardinality with Eq::{equal, not_equal}

///|
pub fn Cardinality::code(self : Cardinality) -> Int32 {
  match self {
    Optional => 1
    Required => 2
    Repeated => 3
  }
}

///|
pub fn Cardinality::of(code : Int32) -> Cardinality? {
  match code {
    1 => Some(Optional)
    2 => Some(Required)
    3 => Some(Repeated)
    _ => None
  }
}

///|
/// The eighteen field kinds, numbered as `descriptor.proto` numbers them.
#derive(Eq)
pub(all) enum Kind {
  Double
  Float
  Int64
  Uint64
  Int32
  Fixed64
  Fixed32
  Bool
  String
  Group
  Message
  Bytes
  Uint32
  Enum
  Sfixed32
  Sfixed64
  Sint32
  Sint64
}

///|
pub extend Kind with Eq::{equal, not_equal}

///|
/// The `descriptor.proto` number of the kind.
pub fn Kind::code(self : Kind) -> Int32 {
  match self {
    Double => 1
    Float => 2
    Int64 => 3
    Uint64 => 4
    Int32 => 5
    Fixed64 => 6
    Fixed32 => 7
    Bool => 8
    String => 9
    Group => 10
    Message => 11
    Bytes => 12
    Uint32 => 13
    Enum => 14
    Sfixed32 => 15
    Sfixed64 => 16
    Sint32 => 17
    Sint64 => 18
  }
}

///|
/// The kind for a `descriptor.proto` number.
pub fn Kind::of(code : Int32) -> Kind? {
  match code {
    1 => Some(Double)
    2 => Some(Float)
    3 => Some(Int64)
    4 => Some(Uint64)
    5 => Some(Int32)
    6 => Some(Fixed64)
    7 => Some(Fixed32)
    8 => Some(Bool)
    9 => Some(String)
    10 => Some(Group)
    11 => Some(Message)
    12 => Some(Bytes)
    13 => Some(Uint32)
    14 => Some(Enum)
    15 => Some(Sfixed32)
    16 => Some(Sfixed64)
    17 => Some(Sint32)
    18 => Some(Sint64)
    _ => None
  }
}

///|
/// Whether the kind is a number, and so packable when repeated.
pub fn Kind::is_numeric(self : Kind) -> Bool {
  match self {
    String | Bytes | Message | Group => false
    _ => true
  }
}

///|
/// Whether the kind is a message or a group, and so needs a nested message.
pub fn Kind::is_message(self : Kind) -> Bool {
  match self {
    Message | Group => true
    _ => false
  }
}

///|
/// Whether the kind is the enum kind.
pub fn Kind::is_enum(self : Kind) -> Bool {
  self == Enum
}

///|
/// A map key: the six scalar kinds a map field's key may take.
#derive(Eq)
pub(all) enum MapKey {
  Bool(Bool)
  Int32(Int32)
  Int64(Int64)
  Uint32(UInt32)
  Uint64(UInt64)
  String(String)
}

///|
pub extend MapKey with Eq::{equal, not_equal}

///|
/// One field value. A composite value holds a reference to a list, map or
/// message, so mutation through it is visible to the message that owns it.
pub(all) enum Value {
  Invalid
  Bool(Bool)
  Int32(Int32)
  Int64(Int64)
  Uint32(UInt32)
  Uint64(UInt64)
  Float(@float.Float)
  Double(Double)
  String(String)
  Bytes(Bytes)
  Enum(Int32)
  Message(&Message)
  ListView(&ListField)
  MapView(&MapField)
}

///|
/// The empty value, used where a field is absent and a `Value` is still
/// required.
pub let invalid : Value = Invalid

///|
pub fn Value::is_valid(self : Value) -> Bool {
  match self {
    Invalid => false
    _ => true
  }
}

///|
/// The value as a bool; aborts when it is not one.
pub fn Value::bool(self : Value) -> Bool {
  match self {
    Bool(v) => v
    _ => abort("value is not a bool")
  }
}

///|
/// The value as an integer; `Int32` and `Int64` both widen.
pub fn Value::int(self : Value) -> Int64 {
  match self {
    Int32(v) => v.to_int64()
    Int64(v) => v
    _ => abort("value is not an integer")
  }
}

///|
/// The value as an unsigned integer; `Uint32` and `Uint64` both widen.
pub fn Value::uint(self : Value) -> UInt64 {
  match self {
    Uint32(v) => v.to_uint64()
    Uint64(v) => v
    _ => abort("value is not an unsigned integer")
  }
}

///|
/// The value as a double; `Float` widens.
pub fn Value::float(self : Value) -> Double {
  match self {
    Float(v) => v.to_double()
    Double(v) => v
    _ => abort("value is not a float")
  }
}

///|
pub fn Value::string(self : Value) -> String {
  match self {
    String(v) => v
    _ => abort("value is not a string")
  }
}

///|
pub fn Value::bytes(self : Value) -> Bytes {
  match self {
    Bytes(v) => v
    _ => abort("value is not bytes")
  }
}

///|
pub fn Value::enum_number(self : Value) -> Int32 {
  match self {
    Enum(v) => v
    _ => abort("value is not an enum")
  }
}

///|
pub fn Value::message(self : Value) -> &Message {
  match self {
    Message(v) => v
    _ => abort("value is not a message")
  }
}

///|
pub fn Value::list(self : Value) -> &ListField {
  match self {
    ListView(v) => v
    _ => abort("value is not a list")
  }
}

///|
pub fn Value::map(self : Value) -> &MapField {
  match self {
    MapView(v) => v
    _ => abort("value is not a map")
  }
}

///|
/// The value as a map key, or `None` when its kind cannot be a key.
pub fn Value::map_key(self : Value) -> MapKey? {
  match self {
    Bool(v) => Some(Bool(v))
    Int32(v) => Some(Int32(v))
    Int64(v) => Some(Int64(v))
    Uint32(v) => Some(Uint32(v))
    Uint64(v) => Some(Uint64(v))
    String(v) => Some(String(v))
    _ => None
  }
}

///|
/// A value for a map key.
pub fn MapKey::value(self : MapKey) -> Value {
  match self {
    Bool(v) => Bool(v)
    Int32(v) => Int32(v)
    Int64(v) => Int64(v)
    Uint32(v) => Uint32(v)
    Uint64(v) => Uint64(v)
    String(v) => String(v)
  }
}

///|
/// Structural equality for scalars; composites compare by identity, because
/// semantic equality is a descriptor-driven walk in `proto.equal`.
pub fn Value::equal(self : Value, other : Value) -> Bool {
  match (self, other) {
    (Invalid, Invalid) => true
    (Bool(a), Bool(b)) => a == b
    (Int32(a), Int32(b)) => a == b
    (Int64(a), Int64(b)) => a == b
    (Uint32(a), Uint32(b)) => a == b
    (Uint64(a), Uint64(b)) => a == b
    (Float(a), Float(b)) => a == b
    (Double(a), Double(b)) => a == b
    (String(a), String(b)) => a == b
    (Bytes(a), Bytes(b)) => a == b
    (Enum(a), Enum(b)) => a == b
    (Message(_), Message(_)) => false
    (ListView(_), ListView(_)) => false
    (MapView(_), MapView(_)) => false
    _ => false
  }
}

///|
/// The bytes of every unknown field a message carried, tag and body included.
pub(all) struct RawFields(Bytes)

///|
pub fn RawFields::from_bytes(bytes : Bytes) -> RawFields {
  RawFields(bytes)
}

///|
pub fn RawFields::bytes(self : RawFields) -> Bytes {
  self.0
}

///|
pub fn RawFields::is_empty(self : RawFields) -> Bool {
  self.0.length() == 0
}

///|
/// Whether the bytes are a syntactically valid sequence of fields.
pub fn RawFields::is_valid(self : RawFields) -> Bool {
  let body = self.0
  let mut at = 0
  while at < body.length() {
    let next = @wire.skip_field(body[:], at~) catch { _ => -1 }
    if next < 0 {
      return false
    }
    at = next
  }
  true
}
