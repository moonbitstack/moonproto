// Wire-format vectors. The expected encodings are the ones the format fixes, not
// values read back from this implementation.

///|
test "varint known encodings" {
  let cases : Array[(UInt64, Bytes)] = [
    (0UL, b"\x00"),
    (1UL, b"\x01"),
    (127UL, b"\x7f"),
    (128UL, b"\x80\x01"),
    (300UL, b"\xac\x02"),
    (16383UL, b"\xff\x7f"),
    (16384UL, b"\x80\x80\x01"),
    (4294967295UL, b"\xff\xff\xff\xff\x0f"),
    (4294967296UL, b"\x80\x80\x80\x80\x10"),
    (0xFFFF_FFFF_FFFF_FFFFUL, b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"),
  ]
  for pair in cases {
    let (value, expected) = pair
    let buf = Buffer()
    append_varint(buf, value)
    assert_eq(buf.to_bytes(), expected)
    let (back, next) = consume_varint(expected[:])
    assert_eq(back, value)
    assert_eq(next, expected.length())
    assert_eq(size_varint(value), expected.length())
  }
}

///|
test "varint refuses an eleventh octet" {
  let eleven = b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x01"
  let hit = try {
    let _ = consume_varint(eleven[:])
    false
  } catch {
    Overflow(_) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "varint refuses a truncated body" {
  let truncated = b"\x80\x80"
  let hit = try {
    let _ = consume_varint(truncated[:])
    false
  } catch {
    Incomplete(_) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "zigzag round-trips and matches the format" {
  let cases : Array[(Int64, UInt64)] = [
    (0L, 0UL),
    (-1L, 1UL),
    (1L, 2UL),
    (-2L, 3UL),
    (2147483647L, 4294967294UL),
    (-2147483648L, 4294967295UL),
    (0x7FFF_FFFF_FFFF_FFFFL, 0xFFFF_FFFF_FFFF_FFFEUL),
    (-0x8000_0000_0000_0000L, 0xFFFF_FFFF_FFFF_FFFFUL),
  ]
  for pair in cases {
    let (signed, unsigned) = pair
    assert_eq(encode_zigzag(signed), unsigned)
    assert_eq(decode_zigzag(unsigned), signed)
  }
}

///|
test "tags round-trip" {
  let cases : Array[(Int32, WireType, Bytes)] = [
    (1, Varint, b"\x08"),
    (2, Fixed64, b"\x11"),
    (3, LengthDelimited, b"\x1a"),
    (4, StartGroup, b"\x23"),
    (5, EndGroup, b"\x2c"),
    (6, Fixed32, b"\x35"),
    (16, LengthDelimited, b"\x82\x01"),
  ]
  for triple in cases {
    let (number, wire, expected) = triple
    let buf = Buffer()
    append_tag(buf, number, wire)
    assert_eq(buf.to_bytes(), expected)
    let (n, w, next) = consume_tag(expected[:])
    assert_eq(n, number)
    assert_true(w == wire)
    assert_eq(next, expected.length())
  }
}

///|
test "tag refuses number zero" {
  let hit = try {
    let _ = consume_tag(b"\x00")
    false
  } catch {
    FieldNumber(_, _) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "fixed widths are little-endian" {
  let buf = Buffer()
  append_fixed32(buf, 0x1234_5678U)
  assert_eq(buf.to_bytes(), b"\x78\x56\x34\x12")
  let (v, next) = consume_fixed32(b"\x78\x56\x34\x12")
  assert_eq(v, 0x1234_5678U)
  assert_eq(next, 4)

  let buf = Buffer()
  append_fixed64(buf, 0x0123_4567_89AB_CDEFUL)
  assert_eq(buf.to_bytes(), b"\xef\xcd\xab\x89\x67\x45\x23\x01")
  let (v, next) = consume_fixed64(b"\xef\xcd\xab\x89\x67\x45\x23\x01")
  assert_eq(v, 0x0123_4567_89AB_CDEFUL)
  assert_eq(next, 8)
}

///|
test "length-delimited bodies and strings" {
  let buf = Buffer()
  append_bytes(buf, b"\x01\x02\x03")
  assert_eq(buf.to_bytes(), b"\x03\x01\x02\x03")
  let (body, next) = consume_bytes(b"\x03\x01\x02\x03")
  assert_eq(body.length(), 3)
  assert_eq(body[0].to_int(), 1)
  assert_eq(next, 4)

  let buf = Buffer()
  append_string(buf, "proto")
  assert_eq(buf.to_bytes(), b"\x05proto")
  let (text, next) = consume_string(b"\x05proto")
  assert_eq(text, "proto")
  assert_eq(next, 6)
}

///|
test "consume_string refuses invalid UTF-8" {
  let hit = try {
    let _ = consume_string(b"\x02\xc3\x28")
    false
  } catch {
    Malformed(_, _, _) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "skip_field walks past every wire type" {
  let buf = Buffer()
  append_tag(buf, 1, Varint)
  append_varint(buf, 300UL)
  append_tag(buf, 2, Fixed32)
  append_fixed32(buf, 7U)
  append_tag(buf, 3, Fixed64)
  append_fixed64(buf, 9UL)
  append_tag(buf, 4, LengthDelimited)
  append_bytes(buf, b"abc")
  let body = buf.to_bytes()
  let mut at = 0
  while at < body.length() {
    at = skip_field(body[:], at~)
  }
  assert_eq(at, body.length())
}

///|
test "skip_field walks a group and its nested fields" {
  let buf = Buffer()
  append_tag(buf, 7, StartGroup)
  append_tag(buf, 1, Varint)
  append_varint(buf, 42UL)
  append_tag(buf, 2, LengthDelimited)
  append_bytes(buf, b"x")
  append_tag(buf, 7, EndGroup)
  let body = buf.to_bytes()
  assert_eq(skip_field(body[:]), body.length())
}

///|
test "a group closed by the wrong number is malformed" {
  let buf = Buffer()
  append_tag(buf, 7, StartGroup)
  append_tag(buf, 8, EndGroup)
  let hit = try {
    let _ = skip_field(buf.to_bytes()[:])
    false
  } catch {
    Malformed(_, _, _) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "groups append both tags" {
  let buf = Buffer()
  append_group(buf, 3, b"\x08\x01")
  assert_eq(buf.to_bytes(), b"\x1b\x08\x01\x1c")
  assert_eq(size_group(3, 2), 4)
}

///|
test "bool and tag codecs" {
  assert_eq(encode_bool(true), 1UL)
  assert_eq(encode_bool(false), 0UL)
  assert_true(decode_bool(2UL))
  assert_false(decode_bool(0UL))
  assert_eq(encode_tag(1, Varint), 8UL)
  let (number, wire) = decode_tag(8UL)
  assert_eq(number, 1)
  assert_true(wire == Varint)
}

///|
test "size_bytes measures prefix and body" {
  assert_eq(size_bytes(0), 1)
  assert_eq(size_bytes(127), 128)
  assert_eq(size_bytes(128), 130)
}
