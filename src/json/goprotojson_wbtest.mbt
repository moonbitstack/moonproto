// Transcribed from protocolbuffers/protobuf-go v1.36.12,
// encoding/protojson/decode_test.go and encoding/protojson/encode_test.go,
// with the range and precision cases from the protobuf conformance suite.

///|
test "protojson: 64-bit integers are strings on the wire" {
  let l = make_field(1, "l", @reflect.Int64, None, "test.M")
  let u = make_field(2, "u", @reflect.Uint64, None, "test.M")
  let desc = message_descriptor("test.M", [l, u])
  let m = @dynamic.Message::new(desc)
  m.set(l, @reflect.Int64(10_000_000_000L))
  m.set(u, @reflect.Uint64(18_446_744_073_709_551_615UL))
  let text = encode(m)
  assert_eq(text, "{\"l\":\"10000000000\",\"u\":\"18446744073709551615\"}")
  let back = @dynamic.Message::new(desc)
  decode(text, back)
  assert_eq(back.get(l).int(), 10_000_000_000L)
  assert_eq(back.get(u).uint(), 18_446_744_073_709_551_615UL)
}

///|
test "protojson: an unquoted 64-bit integer keeps every digit" {
  let l = make_field(1, "l", @reflect.Int64, None, "test.M")
  let desc = message_descriptor("test.M", [l])
  let m = @dynamic.Message::new(desc)
  decode("{\"l\":9223372036854774784}", m)
  assert_eq(m.get(l).int(), 9223372036854774784L)
  let minimum = @dynamic.Message::new(desc)
  decode("{\"l\":-9223372036854775808}", minimum)
  assert_eq(minimum.get(l).int(), 0L - 0x7FFF_FFFF_FFFF_FFFFL - 1L)
}

///|
test "protojson: a quoted exponent is an integer" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  decode("{\"i\":\"1e5\"}", m)
  assert_eq(m.get(i).int(), 100000L)
}

///|
test "protojson: out-of-range integers are refused" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let u = make_field(2, "u", @reflect.Uint32, None, "test.M")
  let desc = message_descriptor("test.M", [i, u])
  let cases = [
    "{\"i\":2147483648}", "{\"i\":-2147483649}", "{\"u\":4294967296}", "{\"u\":\"\"}",
  ]
  for text in cases {
    let m = @dynamic.Message::new(desc)
    let hit = try {
      decode(text, m)
      false
    } catch {
      BadValue(_) => true
      _ => false
    }
    assert_true(hit)
  }
}

///|
test "protojson: a top-level null is refused" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  let hit = try {
    decode("null", m)
    false
  } catch {
    Syntax(_) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "protojson: a null member clears the field" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(9))
  decode("{\"i\":null}", m)
  assert_true(!m.has(i))
}

///|
test "protojson: an out-of-range double is refused" {
  let d = make_field(1, "d", @reflect.Double, None, "test.M")
  let desc = message_descriptor("test.M", [d])
  let m = @dynamic.Message::new(desc)
  let hit = try {
    decode("{\"d\":1.89769e+308}", m)
    false
  } catch {
    BadValue(_) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "protojson: bytes are base64 and enums are named" {
  register_enum()
  let by = make_field(1, "by", @reflect.Bytes, None, "test.M")
  let e = make_field(2, "e", @reflect.Enum, Some("test.Color"), "test.M")
  let desc = message_descriptor("test.M", [by, e])
  let m = @dynamic.Message::new(desc)
  m.set(by, @reflect.Bytes(b"\x01\x02"))
  m.set(e, @reflect.Enum(2))
  assert_eq(encode(m), "{\"by\":\"AQI=\",\"e\":\"BAR\"}")
  let back = @dynamic.Message::new(desc)
  decode("{\"by\":\"AQI=\",\"e\":1}", back)
  assert_eq(back.get(by).bytes(), b"\x01\x02")
  assert_eq(back.get(e).enum_number(), 1)
}

///|
test "protojson: a FieldMask path changes from camel case to snake case" {
  // The well-known types must be registered so the nested message resolves to
  // google.protobuf.FieldMask rather than an unresolvable type name.
  @known.register_all()
  let mask = {
    ..make_field(1, "mask", @reflect.Message, None, "test.M"),
    message_type: Some("google.protobuf.FieldMask"),
    has_presence: true,
  }
  let desc = message_descriptor("test.M", [mask])
  let m = @dynamic.Message::new(desc)
  decode("{\"mask\":\"foo,barBaz\"}", m)
  let paths = m.get(mask).message().descriptor().field_by_number(1)
  assert_true(paths is Some(_))
  assert_eq(encode(m), "{\"mask\":\"foo,bar_baz\"}")
}
