// The well-known types build, register, and encode through the shared codecs.

///|
fn find(name : String) -> @reflect.MessageDescriptor {
  let found = message_descriptor(name) catch { _ => None }
  match found {
    Some(message) => message
    None => abort("missing " + name)
  }
}

///|
test "Timestamp encodes as its JSON string" {
  register_all()
  let desc = find("google.protobuf.Timestamp")
  let m = @dynamic.Message::new(desc)
  for field in desc.fields {
    if field.name == "seconds" {
      m.set(field, @reflect.Int64(0L))
    }
  }
  assert_eq(@json.encode(m), "\"1970-01-01T00:00:00Z\"")
}

///|
test "Duration encodes as its JSON string" {
  register_all()
  let desc = find("google.protobuf.Duration")
  let m = @dynamic.Message::new(desc)
  for field in desc.fields {
    if field.name == "seconds" {
      m.set(field, @reflect.Int64(2L))
    }
    if field.name == "nanos" {
      m.set(field, @reflect.Int32(250_000_000))
    }
  }
  assert_eq(@json.encode(m), "\"2.250000000s\"")
}

///|
test "the wrappers carry one scalar" {
  register_all()
  let desc = find("google.protobuf.Int32Value")
  let m = @dynamic.Message::new(desc)
  for field in desc.fields {
    m.set(field, @reflect.Int32(42))
  }
  assert_eq(@json.encode(m), "42")
  let encoded = @proto.encode(m)
  let back = @dynamic.Message::new(desc)
  @proto.decode(encoded, back)
  for field in desc.fields {
    assert_eq(back.get(field).int(), 42L)
  }
}

///|
test "Value, Struct and ListValue exist with the right shape" {
  register_all()
  let value = find("google.protobuf.Value")
  assert_eq(value.oneofs.length(), 1)
  assert_eq(value.fields.length(), 6)
  let struct_ = find("google.protobuf.Struct")
  assert_eq(struct_.fields.length(), 1)
  assert_true(struct_.fields[0].is_map)
  let list = find("google.protobuf.ListValue")
  assert_eq(list.fields.length(), 1)
}
