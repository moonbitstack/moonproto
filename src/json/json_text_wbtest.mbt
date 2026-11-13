// What the text side owes a caller beyond the mapping itself: a refusal that
// says where the document stopped being JSON, a member that appears twice, the
// two base64 alphabets the mapping takes, and UTF-8 left as UTF-8.

///|
test "a syntax error names the line and the column" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  let reason = try {
    decode("{\n  \"i\": ,\n}", m)
    ""
  } catch {
    Syntax(reason) => reason
    _ => ""
  }
  // A refusal that only says "not JSON" sends the caller back to the whole
  // document; this one points at the character.
  assert_true(reason.contains("line 2, column 8"))
}

///|
test "text after the document is refused" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  let hit = try {
    decode("{\"i\":1}{}", m)
    false
  } catch {
    Syntax(_) => true
    _ => false
  }
  assert_true(hit)
}

///|
test "a member declared twice is refused" {
  let i = make_field(1, "i", @reflect.Int32, None, "test.M")
  let desc = message_descriptor("test.M", [i])
  let m = @dynamic.Message::new(desc)
  let hit = try {
    decode("{\"i\":1,\"i\":2}", m)
    false
  } catch {
    Syntax(_) => true
    _ => false
  }
  assert_true(hit)
  // The document never reached the message, so the field is still unset.
  assert_eq(m.has(i), false)
}

///|
test "one field named twice, once by each of its names, is refused" {
  let declared = make_field(1, "foo_bar", @reflect.Int32, None, "test.M")
  let field = { ..declared, json_name: "fooBar", }
  let desc = message_descriptor("test.M", [field])
  let m = @dynamic.Message::new(desc)
  let reason = try {
    decode("{\"fooBar\":1,\"foo_bar\":2}", m)
    ""
  } catch {
    Syntax(reason) => reason
    _ => ""
  }
  assert_eq(reason, "duplicate field foo_bar")
  assert_eq(m.get(field).int(), 1L)
}

///|
test "bytes take either base64 alphabet, and the padding is optional" {
  let b = make_field(1, "b", @reflect.Bytes, None, "test.M")
  let desc = message_descriptor("test.M", [b])
  for text in ["+/8=", "-_8=", "+/8", "-_8"] {
    let m = @dynamic.Message::new(desc)
    decode("{\"b\":\"" + text + "\"}", m)
    assert_eq(m.get(b).bytes(), b"\xfb\xff")
  }
  let m = @dynamic.Message::new(desc)
  m.set(b, @reflect.Bytes(b"\xfb\xff"))
  // Written as the mapping's own spelling: the standard alphabet, padded.
  assert_eq(encode(m), "{\"b\":\"+/8=\"}")
}

///|
test "a byte string outside both alphabets is refused" {
  let b = make_field(1, "b", @reflect.Bytes, None, "test.M")
  let desc = message_descriptor("test.M", [b])
  for text in ["+*8=", "A", "AAAAA"] {
    let m = @dynamic.Message::new(desc)
    let hit = try {
      decode("{\"b\":\"" + text + "\"}", m)
      false
    } catch {
      BadBase64(_) => true
      _ => false
    }
    assert_true(hit)
  }
}

///|
test "a string keeps its UTF-8 rather than being escaped" {
  let s = make_field(1, "s", @reflect.String, None, "test.M")
  let desc = message_descriptor("test.M", [s])
  let m = @dynamic.Message::new(desc)
  m.set(s, @reflect.String("月"))
  assert_eq(encode(m), "{\"s\":\"月\"}")
  let back = @dynamic.Message::new(desc)
  decode("{\"s\":\"月\"}", back)
  assert_eq(back.get(s).string(), "月")
}
