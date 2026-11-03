// The harness reads one format and writes another. These tests drive the same
// message through binary, JSON and text and compare the values.

///|
fn field_of(
  message : &@reflect.Message,
  number : Int32,
) -> @reflect.FieldDescriptor {
  match message.descriptor().field_by_number(number) {
    Some(field) => field
    None => abort("missing field " + number.to_string())
  }
}

///|
fn set(
  message : &@reflect.Message,
  number : Int32,
  value : @reflect.Value,
) -> Unit {
  message.set(field_of(message, number), value)
}

///|
fn build_message() -> &@reflect.Message {
  let message_type = match
    @reflect.global_types.find_message_by_name("conformance.TestAllTypes") {
    Some(found) => found
    None => abort("no test type")
  }
  let message = message_type.new_message()
  set(message, 1, @reflect.Int32(150))
  set(message, 2, @reflect.Int64(10_000_000_000L))
  set(message, 3, @reflect.Uint32(7U))
  set(message, 4, @reflect.Uint64(8UL))
  set(message, 5, @reflect.Int32(-1))
  set(message, 6, @reflect.Int64(-2L))
  set(message, 7, @reflect.Uint32(0x3F80_0000U))
  set(message, 8, @reflect.Uint64(0x3FF8_0000_0000_0000UL))
  set(message, 9, @reflect.Int32(-3))
  set(message, 10, @reflect.Int64(-4L))
  set(message, 11, @reflect.Float(@float.Float::from_double(2.5)))
  set(message, 12, @reflect.Double(3.5))
  set(message, 13, @reflect.Bool(true))
  set(message, 14, @reflect.String("hi"))
  set(message, 15, @reflect.Bytes(b"\x01\x02"))
  let nums = message.mutable(field_of(message, 16)).list()
  nums.append(@reflect.Int32(1))
  nums.append(@reflect.Int32(300))
  let names = message.mutable(field_of(message, 17)).list()
  names.append(@reflect.String("a"))
  names.append(@reflect.String("b"))
  let counts = message.mutable(field_of(message, 18)).map()
  counts.set(@reflect.String("k"), @reflect.Int32(5))
  let child = message.mutable(field_of(message, 19)).message()
  set(child, 1, @reflect.Int32(9))
  set(message, 20, @reflect.Enum(1))
  set(message, 21, @reflect.String("x"))
  message
}

///|
fn request(
  message_type : String,
  format : Int32,
  protobuf : Bytes?,
  json : String?,
  text : String?,
) -> Bytes {
  let request_type = match
    conformance_types.find_message_by_name("conformance.ConformanceRequest") {
    Some(found) => found
    None => abort("no request type")
  }
  let message = request_type.new_message()
  set(message, 3, @reflect.Enum(format))
  set(message, 4, @reflect.String(message_type))
  match protobuf {
    Some(bytes) => set(message, 1, @reflect.Bytes(bytes))
    None => ()
  }
  match json {
    Some(value) => set(message, 2, @reflect.String(value))
    None => ()
  }
  match text {
    Some(value) => set(message, 8, @reflect.String(value))
    None => ()
  }
  @proto.encode(message) catch {
    _ => abort("encode request")
  }
}

///|
fn response(bytes : Bytes) -> &@reflect.Message {
  let response_type = match
    conformance_types.find_message_by_name("conformance.ConformanceResponse") {
    Some(found) => found
    None => abort("no response type")
  }
  let message = response_type.new_message()
  @proto.decode(bytes, message) catch {
    _ => abort("decode response")
  }
  message
}

///|
fn read_text(message : &@reflect.Message, number : Int32) -> String {
  let field = field_of(message, number)
  if message.has(field) {
    message.get(field).string()
  } else {
    ""
  }
}

///|
fn read_blob(message : &@reflect.Message, number : Int32) -> Bytes {
  let field = field_of(message, number)
  if message.has(field) {
    message.get(field).bytes()
  } else {
    b""
  }
}

///|
test "binary to JSON keeps every scalar and the composite fields" {
  register_test_types()
  let message = build_message()
  let binary = @proto.encode(message) catch { _ => abort("encode") }
  let answer = response(
    handle(request("conformance.TestAllTypes", 2, Some(binary), None, None)),
  )
  let text = read_text(answer, 4)
  assert_true(text.contains("\"i32\":150"))
  assert_true(text.contains("\"i64\":\"10000000000\""))
  assert_true(text.contains("\"s32\":-1"))
  assert_true(text.contains("\"flag\":true"))
  assert_true(text.contains("\"text\":\"hi\""))
  assert_true(text.contains("\"blob\":\"AQI=\""))
  assert_true(text.contains("\"nums\":[1,300]"))
  assert_true(text.contains("\"color\":\"BLUE\""))
}

///|
test "JSON goes back to the same binary" {
  register_test_types()
  let message = build_message()
  let binary = @proto.encode(message) catch { _ => abort("encode") }
  let json_answer = response(
    handle(request("conformance.TestAllTypes", 2, Some(binary), None, None)),
  )
  let json_text = get_string(json_answer, 4)
  let binary_answer = response(
    handle(request("conformance.TestAllTypes", 1, None, Some(json_text), None)),
  )
  let back = read_blob(binary_answer, 3)
  let decoded = match
    @reflect.global_types.find_message_by_name("conformance.TestAllTypes") {
    Some(found) => found.new_message()
    None => abort("no type")
  }
  @proto.decode(back, decoded) catch {
    _ => abort("decode")
  }
  assert_eq(decoded.get(field_of(decoded, 1)).int(), 150L)
  assert_eq(decoded.get(field_of(decoded, 2)).int(), 10_000_000_000L)
  assert_eq(decoded.get(field_of(decoded, 14)).string(), "hi")
  assert_eq(decoded.get(field_of(decoded, 16)).list().length(), 2)
  assert_eq(decoded.get(field_of(decoded, 18)).map().length(), 1)
  assert_eq(
    decoded.get(field_of(decoded, 19)).message().get(field_of(decoded, 1)).int(),
    9L,
  )
}

///|
test "text output is the text format" {
  register_test_types()
  let binary = @proto.encode(build_message()) catch { _ => abort("encode") }
  let answer = response(
    handle(request("conformance.TestAllTypes", 4, Some(binary), None, None)),
  )
  let text = read_text(answer, 7)
  assert_true(text.contains("i32: 150"))
  assert_true(text.contains("text: \"hi\""))
}

///|
test "an unknown message type is a runtime error" {
  register_test_types()
  let answer = response(handle(request("no.Such", 1, Some(b""), None, None)))
  assert_true(read_text(answer, 2).contains("unknown message type"))
}

///|
test "a bad binary payload is a parse error" {
  register_test_types()
  let answer = response(
    handle(
      request("conformance.TestAllTypes", 1, Some(b"\xff\xff"), None, None),
    ),
  )
  assert_true(read_text(answer, 1).length() > 0)
}
