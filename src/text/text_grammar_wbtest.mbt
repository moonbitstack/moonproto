// The text format's grammar beyond one field per line: separators, lists,
// literal forms and the cases the reference parser refuses.

///|
test "a field may end with one separator" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let s = make_field(2, "s", @reflect.String, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [i, s])
  let m = @dynamic.Message::new(desc)
  decode("i: 1, s: \"x\";", m)
  assert_eq(m.get(i).int(), 1L)
  assert_eq(m.get(s).string(), "x")
  // A second separator has no field to introduce, so the parser stops there.
  let doubled = try {
    decode("i: 1,,", @dynamic.Message::new(desc))
    false
  } catch {
    _ => true
  }
  assert_true(doubled)
}

///|
test "a repeated field accepts a bracketed list" {
  let r = make_field(1, "r", @reflect.Int32, @reflect.Repeated, None, "test.M")
  let desc = message_descriptor("test.M", [r])
  let m = @dynamic.Message::new(desc)
  decode("r: [1, 2, 3]", m)
  assert_eq(m.get(r).list().length(), 3)
  assert_eq(m.get(r).list().get(2).int(), 3L)
  let trailing = try {
    decode("r: [1,]", @dynamic.Message::new(desc))
    false
  } catch {
    _ => true
  }
  assert_true(trailing)
  // Two numbers with no separator are two tokens, not one value.
  let missing = try {
    decode("r: [1 2]", @dynamic.Message::new(desc))
    false
  } catch {
    _ => true
  }
  assert_true(missing)
}

///|
test "adjacent string literals join into one value" {
  let s = make_field(1, "s", @reflect.String, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [s])
  let m = @dynamic.Message::new(desc)
  decode("s: 'first' \"second\"\n'third'", m)
  assert_eq(m.get(s).string(), "firstsecondthird")
}

///|
test "octal and hexadecimal integers carry their base" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let l = make_field(2, "l", @reflect.Int64, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [i, l])
  let m = @dynamic.Message::new(desc)
  decode("i: 017777777777 l: -01000000000000000000000", m)
  assert_eq(m.get(i).int(), 2147483647L)
  assert_eq(m.get(l).int(), 0L - 0x7FFF_FFFF_FFFF_FFFFL - 1L)
  let hex = @dynamic.Message::new(desc)
  decode("i: 0x7FFFFFFF", hex)
  assert_eq(hex.get(i).int(), 2147483647L)
}

///|
test "an integer that does not fit its field is refused" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let u = make_field(2, "u", @reflect.Uint32, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [i, u])
  for
    input in [
      "i: 2147483648", "i: -2147483649", "i: 0x80000000", "i: 020000000000", "u: 4294967296",
      "u: -1",
    ] {
    let refused = try {
      decode(input, @dynamic.Message::new(desc))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "float literals take the spellings the format allows" {
  let d = make_field(1, "d", @reflect.Double, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [d])
  let inf = @dynamic.Message::new(desc)
  decode("d: INFINITY", inf)
  assert_true(inf.get(d).float().is_inf())
  let negative_nan = @dynamic.Message::new(desc)
  decode("d: -nAn", negative_nan)
  assert_true(negative_nan.get(d).float().is_nan())
  // An exponent past the range of the literal still has a defined value.
  let overflow = @dynamic.Message::new(desc)
  decode("d: 1e18446744073709551616", overflow)
  assert_true(overflow.get(d).float() > 0.0)
  assert_true(overflow.get(d).float().is_inf())
  for input in ["d: 012", "d: 0x1", "d: 1e"] {
    let refused = try {
      decode(input, @dynamic.Message::new(desc))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "a negative zero keeps its sign on the way out" {
  let d = make_field(1, "d", @reflect.Double, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [d])
  let m = @dynamic.Message::new(desc)
  decode("d: -0", m)
  assert_eq(encode(m), "d: -0\n")
}

///|
test "a string literal cannot span lines" {
  let s = make_field(1, "s", @reflect.String, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [s])
  let refused = try {
    decode("s: 'first line\nsecond line'", @dynamic.Message::new(desc))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "escape sequences cover the control characters" {
  let b = make_field(1, "b", @reflect.Bytes, @reflect.Optional, None, "test.M")
  let desc = message_descriptor("test.M", [b])
  let m = @dynamic.Message::new(desc)
  decode("b: '\\a\\b\\f\\n\\r\\t\\v\\?'", m)
  assert_eq(m.get(b).bytes(), b"\x07\x08\x0c\x0a\x0d\x09\x0b?")
}

///|
test "a reserved name is skipped" {
  let i = make_field(1, "i", @reflect.Int32, @reflect.Optional, None, "test.M")
  let desc : @reflect.MessageDescriptor = {
    ..message_descriptor("test.M", [i]),
    reserved_names: ["reserved_field"],
  }
  let m = @dynamic.Message::new(desc)
  decode("reserved_field: { a: 123 } i: 7", m)
  assert_eq(m.get(i).int(), 7L)
}

///|
test "a closed enum refuses a number it does not declare" {
  let kind : @reflect.EnumDescriptor = {
    name: "Kind",
    full_name: "text.Kind",
    values: [
      { name: "KIND_ZERO", number: 0, full_name: "text.Kind.KIND_ZERO", },
    ],
    closed: true,
    file_path: "text.proto",
  }
  let file : @reflect.FileDescriptor = {
    path: "text.proto",
    package_name: "text",
    syntax: @reflect.Proto2,
    messages: [],
    enums: [kind],
    services: [],
    extensions: [],
    dependencies: [],
    public_dependencies: [],
    edition: None,
    option_map: [],
  }
  @reflect.global_files.register(file) catch {
    _ => ()
  }
  let field : @reflect.FieldDescriptor = {
    ..make_field(1, "kind", @reflect.Enum, @reflect.Optional, None, "test.M"),
    enum_type: Some("text.Kind"),
  }
  let desc = message_descriptor("test.M", [field])
  let m = @dynamic.Message::new(desc)
  decode("kind: KIND_ZERO", m)
  assert_eq(m.get(field).enum_number(), 0)
  let refused = try {
    decode("kind: 42", @dynamic.Message::new(desc))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}
