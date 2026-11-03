// Field numbers are the 29-bit integers a tag carries.

///|
pub type FieldNumber = Int32

///|
/// The five wire types a tag's low three bits select. The two group types are
/// deprecated but still appear in proto2 messages, so they are decoded rather
/// than rejected.
#derive(Eq)
pub(all) enum WireType {
  Varint
  Fixed64
  LengthDelimited
  StartGroup
  EndGroup
  Fixed32
}

///|
/// The tag's low three bits.
pub extend WireType with Eq::{equal, not_equal}

///|
/// The tag's low three bits.
pub fn WireType::code(self : WireType) -> Int32 {
  match self {
    Varint => 0
    Fixed64 => 1
    LengthDelimited => 2
    StartGroup => 3
    EndGroup => 4
    Fixed32 => 5
  }
}

///|
/// The wire type for a tag's low three bits, or `None` when the value is not a
/// wire type at all.
pub fn WireType::of(code : Int32) -> WireType? {
  match code {
    0 => Some(Varint)
    1 => Some(Fixed64)
    2 => Some(LengthDelimited)
    3 => Some(StartGroup)
    4 => Some(EndGroup)
    5 => Some(Fixed32)
    _ => None
  }
}

///|
/// A wire-format refusal. The offset is where the reader stopped, `got` is what
/// it saw and `want` is what the format required.
pub(all) suberror Refused {
  /// The buffer ended at `at` before the value was complete.
  Incomplete(Int32)
  /// The bytes at `at` are not a valid encoding; `got` and `want` state why.
  Malformed(Int32, Int32, Int32)
  /// A varint at `at` needs more than ten octets.
  Overflow(Int32)
  /// The field number decoded at `at` is outside the valid range.
  FieldNumber(Int32, Int32)
  /// The three-bit wire type at `at` is not one of the five.
  WireType(Int32, Int32)
  /// Nesting reached `limit`.
  Recursion(Int32)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Incomplete(at) => logger.write_string("incomplete at " + at.to_string())
    Malformed(at, got, want) =>
      logger.write_string(
        "malformed at " +
        at.to_string() +
        ": got " +
        got.to_string() +
        ", want " +
        want.to_string(),
      )
    Overflow(at) => logger.write_string("varint overflow at " + at.to_string())
    FieldNumber(at, got) =>
      logger.write_string(
        "field number " + got.to_string() + " at " + at.to_string(),
      )
    WireType(at, got) =>
      logger.write_string(
        "wire type " + got.to_string() + " at " + at.to_string(),
      )
    Recursion(limit) =>
      logger.write_string("recursion limit " + limit.to_string())
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// The depth and byte ceiling a reader applies to one message.
pub(all) struct Limits {
  depth : Int32
  size : Int32
}

///|
/// The reference defaults: ten thousand levels, and no practical byte ceiling.
pub let limits : Limits = { depth: 10000, size: 0x7FFF_FFFF, }

///|
/// The largest field number the format allows.
pub let max_field_number : Int32 = 0x1FFF_FFFF

///|
/// The offset of the first byte past `count` bytes starting at `at`, refusing
/// when the buffer is shorter.
fn need(at : Int32, count : Int32, limit : Int32) -> Int32 raise Refused {
  if at < 0 || count < 0 || at > limit || count > limit - at {
    raise Incomplete(at)
  }
  at + count
}

///|
/// Append a base-128 varint: seven bits per octet, high bit set on every octet
/// but the last.
pub fn append_varint(buf : Buffer, value : UInt64) -> Unit {
  let mut rest = value
  while rest >= 0x80UL {
    buf.write_byte(((rest & 0x7FUL) | 0x80UL).to_byte())
    rest = rest >> 7
  }
  buf.write_byte(rest.to_byte())
}

///|
/// Append a tag, itself a varint of `(number << 3) | wire_type`.
pub fn append_tag(buf : Buffer, number : FieldNumber, wire : WireType) -> Unit {
  append_varint(buf, (number.to_uint64() << 3) | wire.code().to_uint64())
}

///|
/// Append a little-endian 32-bit value.
pub fn append_fixed32(buf : Buffer, value : UInt32) -> Unit {
  buf.write_byte((value & 0xFFU).to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).to_byte())
}

///|
/// Append a little-endian 64-bit value.
pub fn append_fixed64(buf : Buffer, value : UInt64) -> Unit {
  append_fixed32(buf, value.to_uint())
  append_fixed32(buf, (value >> 32).to_uint())
}

///|
/// Append a length-delimited body: a varint length then the bytes.
pub fn append_bytes(buf : Buffer, value : BytesView) -> Unit {
  append_varint(buf, value.length().to_uint64())
  buf.write_bytes(value)
}

///|
/// Append a length-delimited string.
pub fn append_string(buf : Buffer, value : StringView) -> Unit {
  let bytes = @utf8.encode(value)
  append_varint(buf, bytes.length().to_uint64())
  buf.write_bytes(bytes)
}

///|
/// Append a start tag, the body, and the matching end tag.
pub fn append_group(
  buf : Buffer,
  number : FieldNumber,
  body : BytesView,
) -> Unit {
  append_tag(buf, number, StartGroup)
  buf.write_bytes(body)
  append_tag(buf, number, EndGroup)
}

///|
/// Read a varint, returning the value and the offset just past it.
pub fn consume_varint(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
) -> (UInt64, Int32) raise Refused {
  let n = min_int(b.length(), limit)
  let mut value = 0UL
  let mut shift = 0
  let mut i = at
  while i < n {
    let byte = b[i].to_uint64()
    if shift == 63 && byte > 1UL {
      raise Overflow(i)
    }
    value = value | ((byte & 0x7FUL) << shift)
    i = i + 1
    if byte < 0x80UL {
      return (value, i)
    }
    shift = shift + 7
    if shift > 63 {
      raise Overflow(i)
    }
  }
  raise Incomplete(i)
}

///|
/// Read a tag, returning the field number, the wire type, and the offset just
/// past it.
pub fn consume_tag(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
) -> (FieldNumber, WireType, Int32) raise Refused {
  let (tag, next) = consume_varint(b, at~, limit~)
  if tag > 0xFFFF_FFFFUL {
    raise Malformed(at, tag.to_int(), 0)
  }
  let number = (tag >> 3).to_int()
  let code = (tag & 7UL).to_int()
  if number < 1 || number > max_field_number {
    raise FieldNumber(at, number)
  }
  match WireType::of(code) {
    Some(wire) => (number, wire, next)
    None => raise WireType(at, code)
  }
}

///|
/// Read a little-endian 32-bit value.
pub fn consume_fixed32(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
) -> (UInt32, Int32) raise Refused {
  let next = need(at, 4, min_int(b.length(), limit))
  let value = b[at].to_uint() |
    (b[at + 1].to_uint() << 8) |
    (b[at + 2].to_uint() << 16) |
    (b[at + 3].to_uint() << 24)
  (value, next)
}

///|
/// Read a little-endian 64-bit value.
pub fn consume_fixed64(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
) -> (UInt64, Int32) raise Refused {
  let (low, next) = consume_fixed32(b, at~, limit~)
  let (high, next2) = consume_fixed32(b, at=next, limit~)
  ((high.to_uint64() << 32) | low.to_uint64(), next2)
}

///|
/// Read a length-delimited body, returning a view of it and the offset just past
/// it.
pub fn consume_bytes(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
) -> (BytesView, Int32) raise Refused {
  let cap = min_int(b.length(), limit)
  let (length, start) = consume_varint(b, at~, limit=cap)
  if length > 0x7FFF_FFFFUL {
    raise Malformed(at, length.to_int(), 0)
  }
  let count = length.to_int()
  let next = need(start, count, cap)
  (b.exact_view(start~, end=next), next)
}

///|
/// Read a length-delimited string, refusing invalid UTF-8 as the format
/// requires.
pub fn consume_string(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
) -> (String, Int32) raise Refused {
  let (body, next) = consume_bytes(b, at~, limit~)
  let text = @utf8.decode(body) catch { _ => raise Malformed(at, 0, 0) }
  (text, next)
}

///|
/// Read a group body up to its matching end tag. The returned view excludes both
/// tags.
fn consume_group_body(
  b : BytesView,
  number : FieldNumber,
  at : Int32,
  limit : Int32,
  depth : Int32,
  limits : Limits,
) -> (BytesView, Int32) raise Refused {
  if depth >= limits.depth {
    raise Recursion(limits.depth)
  }
  let mut i = at
  while true {
    let (inner, wire, next) = consume_tag(b, at=i, limit~)
    if wire == EndGroup {
      if inner != number {
        raise Malformed(i, inner, number)
      }
      return (b.exact_view(start=at, end=i), next)
    }
    i = skip_value(b, inner, wire, next, limit, depth + 1, limits)
  }
  abort("unreachable")
}

///|
/// Skip one field whose tag has already been read.
fn skip_value(
  b : BytesView,
  number : FieldNumber,
  wire : WireType,
  at : Int32,
  limit : Int32,
  depth : Int32,
  limits : Limits,
) -> Int32 raise Refused {
  match wire {
    Varint => {
      let (_, next) = consume_varint(b, at~, limit~)
      next
    }
    Fixed64 => need(at, 8, min_int(b.length(), limit))
    LengthDelimited => {
      let (_, next) = consume_bytes(b, at~, limit~)
      next
    }
    StartGroup => {
      let (_, next) = consume_group_body(b, number, at, limit, depth, limits)
      next
    }
    EndGroup => at
    Fixed32 => need(at, 4, min_int(b.length(), limit))
  }
}

///|
/// Skip one whole field, returning the offset just past it.
pub fn skip_field(
  b : BytesView,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
  limits~ : Limits = limits,
) -> Int32 raise Refused {
  let (number, wire, next) = consume_tag(b, at~, limit~)
  skip_value(b, number, wire, next, min_int(b.length(), limit), 0, limits)
}

///|
/// The number of octets a varint occupies.
pub fn size_varint(value : UInt64) -> Int32 {
  let mut count = 1
  let mut rest = value
  while rest >= 0x80UL {
    rest = rest >> 7
    count = count + 1
  }
  count
}

///|
/// The number of octets a tag occupies.
pub fn size_tag(number : FieldNumber) -> Int32 {
  size_varint((number.to_uint64() << 3) | 0UL)
}

///|
/// The number of octets a length-delimited body occupies, prefix included.
pub fn size_bytes(length : Int32) -> Int32 {
  size_varint(length.to_uint64()) + length
}

///|
/// The number of octets a group occupies, both tags included.
pub fn size_group(number : FieldNumber, body : Int32) -> Int32 {
  size_tag(number) + body + size_tag(number)
}

///|
/// Map a signed integer to an unsigned one that stays short for small
/// magnitudes: `(n << 1) ^ (n >> 63)`.
pub fn encode_zigzag(value : Int64) -> UInt64 {
  ((value << 1) ^ (value >> 63)).reinterpret_as_uint64()
}

///|
/// The inverse of `encode_zigzag`.
pub fn decode_zigzag(value : UInt64) -> Int64 {
  (value >> 1).reinterpret_as_int64() ^ -(value & 1UL).reinterpret_as_int64()
}

///|
/// `true` is one, `false` is zero.
pub fn encode_bool(value : Bool) -> UInt64 {
  if value {
    1UL
  } else {
    0UL
  }
}

///|
/// Any non-zero varint is `true`.
pub fn decode_bool(value : UInt64) -> Bool {
  value != 0UL
}

///|
/// A tag as one integer.
pub fn encode_tag(number : FieldNumber, wire : WireType) -> UInt64 {
  (number.to_uint64() << 3) | wire.code().to_uint64()
}

///|
/// Split a tag into its number and wire type.
pub fn decode_tag(tag : UInt64) -> (FieldNumber, WireType) raise Refused {
  if tag > 0xFFFF_FFFFUL {
    raise Malformed(0, tag.to_int(), 0)
  }
  let number = (tag >> 3).to_int()
  let code = (tag & 7UL).to_int()
  if number < 1 || number > max_field_number {
    raise FieldNumber(0, number)
  }
  match WireType::of(code) {
    Some(wire) => (number, wire)
    None => raise WireType(0, code)
  }
}

///|
/// The smaller of two bounds.
fn min_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Read a group body after its start tag. `at` is the offset just past the
/// start tag; the returned view excludes both tags.
pub fn consume_group(
  b : BytesView,
  number : FieldNumber,
  at~ : Int32 = 0,
  limit~ : Int32 = 0x7FFF_FFFF,
  limits~ : Limits = limits,
) -> (BytesView, Int32) raise Refused {
  consume_group_body(b, number, at, min_int(b.length(), limit), 0, limits)
}
