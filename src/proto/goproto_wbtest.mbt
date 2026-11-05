// Transcribed from protocolbuffers/protobuf-go v1.36.12: proto/encode_test.go,
// proto/decode_test.go, proto/merge_test.go, proto/equal_test.go,
// proto/reset_test.go, proto/size_test.go and proto/repeated_test.go.

///|
test "proto: Marshal and Unmarshal keep a scalar alongside an unknown field" {
  let i = scalar_field(1, "i", @reflect.Int32)
  let desc = message_descriptor("test.Scalars", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(150))
  let extra = b"\x48\x07"
  let bytes = encode(m) + extra
  let back = @dynamic.Message::new(desc)
  decode(bytes, back)
  assert_eq(back.get(i).int(), 150L)
  assert_eq(back.get_unknown().bytes(), extra)
  assert_eq(encode(back), bytes)
}

///|
test "proto: Merge appends repeated values and keeps the destination's own" {
  let nums = repeated_field(1, "nums", @reflect.Int32, true)
  let desc = message_descriptor("test.Scalars", [nums])
  let left = @dynamic.Message::new(desc)
  let right = @dynamic.Message::new(desc)
  let left_list = left.mutable(nums).list()
  left_list.append(@reflect.Int32(1))
  let right_list = right.mutable(nums).list()
  right_list.append(@reflect.Int32(2))
  right_list.append(@reflect.Int32(3))
  merge(left, right as &@reflect.Message)
  let merged = left.get(nums).list()
  assert_eq(merged.length(), 3)
  assert_eq(merged.get(0).int(), 1L)
  assert_eq(merged.get(1).int(), 2L)
  assert_eq(merged.get(2).int(), 3L)
}

///|
test "proto: Clone is equal to its source and independent of later edits" {
  let i = scalar_field(1, "i", @reflect.Int32)
  let desc = message_descriptor("test.Scalars", [i])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(7))
  let copy = clone(m)
  assert_true(equal(m, copy))
  copy.set(i, @reflect.Int32(8))
  assert_true(!equal(m, copy))
  assert_eq(m.get(i).int(), 7L)
}

///|
test "proto: Reset clears fields, lists and unknown bytes" {
  let i = scalar_field(1, "i", @reflect.Int32)
  let nums = repeated_field(2, "nums", @reflect.Int32, true)
  let desc = message_descriptor("test.Scalars", [i, nums])
  let m = @dynamic.Message::new(desc)
  m.set(i, @reflect.Int32(7))
  m.mutable(nums).list().append(@reflect.Int32(9))
  m.set_unknown(@reflect.RawFields::from_bytes(b"\x48\x07"))
  reset(m)
  assert_true(!m.has(i))
  assert_true(!m.has(nums))
  assert_eq(m.get_unknown().bytes(), b"")
  assert_eq(size(m), 0)
  // A cleared repeated field is absent; asking for it again yields an empty
  // container, which is Go's `GetNums()` after `proto.Reset`.
  assert_eq(m.mutable(nums).list().length(), 0)
}

///|
test "proto: Size is the encoded length for every scalar shape" {
  let kinds : Array[@reflect.Kind] = [
    @reflect.Int32,
    @reflect.Int64,
    @reflect.Uint32,
    @reflect.Uint64,
    @reflect.Sint32,
    @reflect.Sint64,
    @reflect.Fixed32,
    @reflect.Fixed64,
    @reflect.Sfixed32,
    @reflect.Sfixed64,
    @reflect.Float,
    @reflect.Double,
    @reflect.Bool,
    @reflect.String,
    @reflect.Bytes,
  ]
  for kind in kinds {
    let f = scalar_field(1, "f", kind)
    let desc = message_descriptor("test.Scalars", [f])
    let m = @dynamic.Message::new(desc)
    m.set(f, @reflect.new_element_value(kind, None))
    assert_eq(size(m), encode(m).length())
  }
}

///|
test "proto: packed and expanded repeated encodings decode to the same list" {
  let nums = repeated_field(1, "nums", @reflect.Int32, true)
  let desc = message_descriptor("test.Scalars", [nums])
  let packed = @dynamic.Message::new(desc)
  let list = packed.mutable(nums).list()
  list.append(@reflect.Int32(1))
  list.append(@reflect.Int32(300))
  let bytes = encode(packed)
  assert_eq(bytes, b"\x0a\x03\x01\xac\x02")
  // An expanded encoding uses one tag per element; the decoder must accept it.
  let expanded = b"\x08\x01\x08\xac\x02"
  let back = @dynamic.Message::new(desc)
  decode(expanded, back)
  let items = back.get(nums).list()
  assert_eq(items.length(), 2)
  assert_eq(items.get(0).int(), 1L)
  assert_eq(items.get(1).int(), 300L)
}
