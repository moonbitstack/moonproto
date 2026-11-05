// Transcribed from protocolbuffers/protobuf-go v1.36.12,
// encoding/protowire/wire_test.go. The expected bytes are the format's fixed
// points, not values read back from this implementation.

///|
test "protowire: the largest varint takes ten octets, an eleventh overflows" {
  let largest = 0xFFFF_FFFF_FFFF_FFFFUL
  let buf = Buffer()
  append_varint(buf, largest)
  assert_eq(buf.to_bytes(), b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01")
  assert_eq(size_varint(largest), 10)
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
test "protowire: a tag may not use an overlong varint" {
  let overlong = b"\x88\x80\x80\x80\x80\x00"
  let hit = try {
    let _ = consume_tag(overlong[:])
    false
  } catch {
    Malformed(_, _, _) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "protowire: zigzag covers zero and both signed extremes" {
  let cases : Array[(Int64, UInt64)] = [
    (0L, 0UL),
    (0L - 1L, 1UL),
    (1L, 2UL),
    (0L - 2L, 3UL),
    (2147483647L, 4294967294UL),
    (0L - 2147483648L, 4294967295UL),
    (0x7FFF_FFFF_FFFF_FFFFL, 0xFFFF_FFFF_FFFF_FFFEUL),
    (0L - 0x7FFF_FFFF_FFFF_FFFFL - 1L, 0xFFFF_FFFF_FFFF_FFFFUL),
  ]
  for pair in cases {
    let (value, wire) = pair
    assert_eq(encode_zigzag(value), wire)
    assert_eq(decode_zigzag(wire), value)
  }
}

///|
test "protowire: a varint with a high bit set in every octet is incomplete" {
  let truncated = b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
  let hit = try {
    let _ = consume_varint(truncated[:])
    false
  } catch {
    Overflow(_) => true
    Incomplete(_) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "protowire: size_varint agrees with the encoder on every boundary" {
  let boundaries : Array[UInt64] = [
    0UL, 1UL, 127UL, 128UL, 16383UL, 16384UL, 2097151UL, 2097152UL, 0xFFFF_FFFFUL,
    0x1_0000_0000UL, 0xFFFF_FFFF_FFFF_FFFFUL,
  ]
  for value in boundaries {
    let buf = Buffer()
    append_varint(buf, value)
    assert_eq(size_varint(value), buf.length())
    let (back, next) = consume_varint(buf.to_bytes()[:])
    assert_eq(back, value)
    assert_eq(next, buf.length())
  }
}
