// Binary encode and decode, and the operations defined on a message rather than
// on a format.

///|
/// How a message is written as bytes.
pub(all) struct MarshalOptions {
  /// Skip the check that every required field is set. Off by default: a message
  /// that would not decode back is worth refusing at the point of writing.
  allow_partial : Bool
  /// Order map entries by key so one message always produces one byte string.
  /// Off by default, because ordering costs a copy of the entry list.
  deterministic : Bool
}

///|
pub let marshal_options : MarshalOptions = {
  allow_partial: false,
  deterministic: false,
}

///|
/// How a message is read from bytes.
pub(all) struct UnmarshalOptions {
  /// Keep what the destination already holds instead of clearing it first. A
  /// repeated field is appended to, and a nested message is merged into.
  merge : Bool
  /// Accept a message whose required fields are missing. Off by default.
  allow_partial : Bool
  /// Drop a field the schema does not declare instead of keeping its bytes for
  /// the next write. Off by default: unknown fields belong to whoever sent them.
  discard_unknown : Bool
  /// How deep a nested message may go before the reader refuses. Nesting is
  /// how a small input asks for unbounded memory, so the limit is a bound on
  /// what an untrusted message may cost.
  recursion_limit : Int32
}

///|
pub let unmarshal_options : UnmarshalOptions = {
  merge: false,
  allow_partial: false,
  discard_unknown: false,
  recursion_limit: 10000,
}

///|
/// A binary refusal. A refusal raised by a lower package travels as a payload
/// rather than as a string, so a caller can still see where the bytes stopped.
pub(all) suberror Refused {
  /// The bytes are not a valid encoding; the payload says where and why.
  Wire(@wire.Refused)
  /// A required field was unset; the payload is its dotted path.
  Required(String)
  /// A nested message's type is not registered under the name the field gives.
  NoType(String)
  /// Nesting passed the limit; the payload is the limit that was in force.
  Recursion(Int32)
  /// A tag carried a wire type the field's kind does not use; the payload is
  /// the field's qualified name.
  Mismatch(String)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Wire(_) => logger.write_string("wire error")
    Required(name) => logger.write_string("required field missing: " + name)
    NoType(name) => logger.write_string("no type registered for " + name)
    Recursion(limit) =>
      logger.write_string("recursion limit " + limit.to_string())
    Mismatch(name) => logger.write_string("type mismatch on " + name)
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// The encoded bytes of `message`. Fields are written in field-number order, so
/// the output depends only on the values, and a field without presence that
/// holds its zero is left out.
pub fn[M : @reflect.Message] encode(
  message : M,
  marshal_options~ : MarshalOptions = marshal_options,
) -> Bytes raise Refused {
  if !marshal_options.allow_partial {
    check_initialized(message)
  }
  let buf = Buffer()
  encode_message(buf, message, marshal_options, 0)
  buf.to_bytes()
}

///|
/// Append the encoded bytes of `message` to `buf`, which is what a message
/// nested in another one is written through.
pub fn[M : @reflect.Message] encode_to(
  buf : Buffer,
  message : M,
  marshal_options~ : MarshalOptions = marshal_options,
) -> Unit raise Refused {
  if !marshal_options.allow_partial {
    check_initialized(message)
  }
  encode_message(buf, message, marshal_options, 0)
}

///|
/// The length `encode` would produce, without keeping the bytes. It is the same
/// walk, so it refuses nothing the encoder would not.
pub fn[M : @reflect.Message] size(message : M) -> Int32 {
  let buf = Buffer()
  encode_message(buf, message, marshal_options, 0) catch {
    _ => ()
  }
  buf.length()
}

///|
/// Read `bytes` into `message`. The destination is a struct with mutable fields,
/// so it is written in place and the caller's binding sees the result; it is
/// cleared first unless `merge` is set.
pub fn[M : @reflect.Message] decode(
  bytes : BytesView,
  message : M,
  unmarshal_options~ : UnmarshalOptions = unmarshal_options,
) -> Unit raise Refused {
  if !unmarshal_options.merge {
    reset(message)
  }
  decode_message(message, bytes, 0, bytes.length(), 0, unmarshal_options)
  if !unmarshal_options.allow_partial {
    check_initialized(message)
  }
}

///|
/// Clear every field and every unknown byte, leaving the message as `new`
/// built it.
pub fn[M : @reflect.Message] reset(message : M) -> Unit {
  let desc = message.descriptor()
  for field in desc.fields {
    message.clear(field)
  }
  message.set_unknown(@reflect.RawFields::from_bytes(b""))
}

///|
/// Merge `source` into `destination`: a repeated field is appended to, a map is
/// merged key by key, a nested message is merged recursively, and a scalar with
/// presence replaces what was there.
pub fn[M : @reflect.Message] merge(
  destination : M,
  source : &@reflect.Message,
) -> Unit {
  source.range(fn(field, value) {
    merge_field(destination, field, value)
    true
  })
  // An extension is not in `desc.fields`, so it needs its own pass.
  source.range_extensions(fn(field, value) {
    merge_field(destination, field, value)
    true
  })
  let unknown = source.get_unknown().bytes()
  if unknown.length() > 0 {
    let joined = Buffer()
    joined.write_bytes(destination.get_unknown().bytes())
    joined.write_bytes(unknown)
    destination.set_unknown(@reflect.RawFields::from_bytes(joined.to_bytes()))
  }
}

///|
/// A deep copy of `message`. `Fresh` is what names the concrete type, so the copy
/// has the same type as its source rather than the trait object behind it.
pub fn[M : @reflect.Message + @reflect.Fresh] clone(message : M) -> M {
  let copy = @reflect.Fresh::fresh(message)
  merge(copy, message as &@reflect.Message)
  copy
}

///|
fn merge_field(
  destination : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  value : @reflect.Value,
) -> Unit {
  if field.is_map {
    let target = destination.mutable(field).map()
    value
    .map()
    .range(fn(key, item) {
      target.set(key, item)
      true
    })
  } else if field.is_list() {
    let target = destination.mutable(field).list()
    let items = value.list()
    for i in 0..<items.length() {
      target.append(items.get(i))
    }
  } else if field.kind.is_message() {
    let target = destination.mutable(field).message()
    merge(target, value.message())
  } else {
    destination.set(field, value)
  }
}

///|
/// Whether two messages have the same fields and values. Presence is part of the
/// answer: a field set to its zero counts as absent when it has no presence, and
/// as a value when it has.
pub fn[M : @reflect.Message] equal(left : M, right : M) -> Bool {
  equal_messages(left as &@reflect.Message, right as &@reflect.Message)
}

///|
fn equal_messages(left : &@reflect.Message, right : &@reflect.Message) -> Bool {
  let desc = left.descriptor()
  for field in desc.fields {
    if !equal_field(left, right, field) {
      return false
    }
  }
  let left_ext = extension_fields(left)
  let right_ext = extension_fields(right)
  if left_ext.length() != right_ext.length() {
    return false
  }
  for field in left_ext {
    if !equal_field(left, right, field) {
      return false
    }
  }
  left.get_unknown().bytes() == right.get_unknown().bytes()
}

///|
fn extension_fields(
  message : &@reflect.Message,
) -> Array[@reflect.FieldDescriptor] {
  let out : Array[@reflect.FieldDescriptor] = []
  message.range_extensions(fn(field, _value) {
    out.push(field)
    true
  })
  out
}

///|
fn equal_field(
  left : &@reflect.Message,
  right : &@reflect.Message,
  field : @reflect.FieldDescriptor,
) -> Bool {
  let has_left = left.has(field)
  let has_right = right.has(field)
  if has_left != has_right {
    return false
  }
  if !has_left {
    return true
  }
  let a = left.get(field)
  let b = right.get(field)
  if field.is_map {
    let ma = a.map()
    let mb = b.map()
    if ma.length() != mb.length() {
      return false
    }
    let mut same = true
    ma.range(fn(key, value) {
      if !mb.has(key) {
        same = false
        false
      } else {
        let other = mb.get(key)
        if !equal_field_value(field, value, other) {
          same = false
          false
        } else {
          true
        }
      }
    })
    if !same {
      return false
    }
  } else if field.is_list() {
    let la = a.list()
    let lb = b.list()
    if la.length() != lb.length() {
      return false
    }
    for i in 0..<la.length() {
      if !equal_field_value(field, la.get(i), lb.get(i)) {
        return false
      }
    }
  } else if !equal_field_value(field, a, b) {
    return false
  }
  true
}

///|
fn equal_field_value(
  field : @reflect.FieldDescriptor,
  a : @reflect.Value,
  b : @reflect.Value,
) -> Bool {
  if field.kind.is_message() {
    equal_messages(a.message(), b.message())
  } else {
    a.equal(b)
  }
}

///|
/// Refuse a message with a required field unset. The refusal names the field by
/// its dotted path, so a nested omission says where it is.
pub fn[M : @reflect.Message] check_initialized(
  message : M,
) -> Unit raise Refused {
  match @reflect.missing_required(message as &@reflect.Message) {
    Some(path) => raise Required(path)
    None => ()
  }
}

// -- encoding ---------------------------------------------------------------

///|
fn encode_message(
  buf : Buffer,
  message : &@reflect.Message,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if depth > 10000 {
    raise Recursion(10000)
  }
  let desc = message.descriptor()
  let fields = sorted_fields(desc.fields)
  for field in fields {
    encode_one_of(buf, message, field, opts, depth)
  }
  // Extensions sit in the message's extension ranges and are keyed by number
  // like any other field, so they encode through the same path.
  let extensions : Array[@reflect.FieldDescriptor] = []
  message.range_extensions(fn(field, _value) {
    extensions.push(field)
    true
  })
  for field in sorted_fields(extensions) {
    encode_one_of(buf, message, field, opts, depth)
  }
  buf.write_bytes(message.get_unknown().bytes())
}

///|
fn encode_one_of(
  buf : Buffer,
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if field.is_map {
    encode_map(buf, message, field, opts, depth)
  } else if field.is_list() {
    encode_list(buf, message, field, opts, depth)
  } else if @reflect.is_populated(message, field) {
    encode_singular(buf, message.get(field), field, opts, depth)
  }
}

///|
fn sorted_fields(
  fields : Array[@reflect.FieldDescriptor],
) -> Array[@reflect.FieldDescriptor] {
  let result = fields.copy()
  let mut i = 1
  while i < result.length() {
    let current = result[i]
    let mut j = i
    while j > 0 && result[j - 1].number > current.number {
      result[j] = result[j - 1]
      j = j - 1
    }
    result[j] = current
    i = i + 1
  }
  result
}

///|
fn encode_list(
  buf : Buffer,
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if !message.has(field) {
    return
  }
  let list = message.get(field).list()
  if list.length() == 0 {
    return
  }
  if field.packed && field.kind.is_numeric() {
    let body = Buffer()
    for i in 0..<list.length() {
      encode_scalar_body(body, field.kind, list.get(i))
    }
    let bytes = body.to_bytes()
    @wire.append_tag(buf, field.number, LengthDelimited)
    @wire.append_bytes(buf, bytes)
  } else {
    for i in 0..<list.length() {
      encode_singular(buf, list.get(i), field, opts, depth)
    }
  }
}

///|
fn encode_map(
  buf : Buffer,
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  if !message.has(field) {
    return
  }
  let map = message.get(field).map()
  let entries : Array[(@reflect.MapKey, @reflect.Value)] = []
  map.range(fn(key, value) {
    entries.push((key, value))
    true
  })
  if opts.deterministic {
    sort_entries(entries)
  }
  match (field.map_key_field, field.map_value_field) {
    (Some(key_field), Some(value_field)) =>
      for entry in entries {
        let body = Buffer()
        encode_singular(body, entry.0.value(), key_field, opts, depth)
        encode_singular(body, entry.1, value_field, opts, depth)
        @wire.append_tag(buf, field.number, LengthDelimited)
        @wire.append_bytes(buf, body.to_bytes())
      }
    _ => ()
  }
}

///|
fn sort_entries(entries : Array[(@reflect.MapKey, @reflect.Value)]) -> Unit {
  let mut i = 1
  while i < entries.length() {
    let current = entries[i]
    let mut j = i
    while j > 0 && compare_map_key(entries[j - 1].0, current.0) > 0 {
      entries[j] = entries[j - 1]
      j = j - 1
    }
    entries[j] = current
    i = i + 1
  }
}

///|
fn compare_map_key(a : @reflect.MapKey, b : @reflect.MapKey) -> Int32 {
  match (a, b) {
    (Bool(x), Bool(y)) => if x == y { 0 } else if x { 1 } else { -1 }
    (Int32(x), Int32(y)) => compare_int(x.to_int64(), y.to_int64())
    (Int64(x), Int64(y)) => compare_int(x, y)
    (Uint32(x), Uint32(y)) => compare_int(x.to_int64(), y.to_int64())
    (Uint64(x), Uint64(y)) => if x == y { 0 } else if x < y { -1 } else { 1 }
    (String(x), String(y)) => if x == y { 0 } else if x < y { -1 } else { 1 }
    _ => 0
  }
}

///|
fn compare_int(a : Int64, b : Int64) -> Int32 {
  if a == b {
    0
  } else if a < b {
    -1
  } else {
    1
  }
}

///|
fn encode_singular(
  buf : Buffer,
  value : @reflect.Value,
  field : @reflect.FieldDescriptor,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  match field.kind {
    @reflect.Message =>
      encode_nested(
        buf,
        value.message(),
        field.number,
        LengthDelimited,
        opts,
        depth,
      )
    @reflect.Group => {
      @wire.append_tag(buf, field.number, StartGroup)
      encode_message(buf, value.message(), opts, depth + 1)
      @wire.append_tag(buf, field.number, EndGroup)
    }
    @reflect.String => {
      @wire.append_tag(buf, field.number, LengthDelimited)
      @wire.append_string(buf, value.string())
    }
    @reflect.Bytes => {
      @wire.append_tag(buf, field.number, LengthDelimited)
      @wire.append_bytes(buf, value.bytes())
    }
    _ => {
      let (wire_type, _) = wire_type_of(field.kind)
      @wire.append_tag(buf, field.number, wire_type)
      encode_scalar_body(buf, field.kind, value)
    }
  }
}

///|
fn encode_nested(
  buf : Buffer,
  message : &@reflect.Message,
  number : Int32,
  wire_type : @wire.WireType,
  opts : MarshalOptions,
  depth : Int32,
) -> Unit raise Refused {
  let body = Buffer()
  encode_message(body, message, opts, depth + 1)
  @wire.append_tag(buf, number, wire_type)
  @wire.append_bytes(buf, body.to_bytes())
}

///|
fn wire_type_of(kind : @reflect.Kind) -> (@wire.WireType, Bool) {
  match kind {
    @reflect.Double | @reflect.Fixed64 | @reflect.Sfixed64 => (Fixed64, true)
    @reflect.Float | @reflect.Fixed32 | @reflect.Sfixed32 => (Fixed32, true)
    @reflect.String | @reflect.Bytes | @reflect.Message | @reflect.Group =>
      (LengthDelimited, false)
    _ => (Varint, true)
  }
}

///|
fn encode_scalar_body(
  buf : Buffer,
  kind : @reflect.Kind,
  value : @reflect.Value,
) -> Unit {
  match kind {
    @reflect.Bool => @wire.append_varint(buf, @wire.encode_bool(value.bool()))
    @reflect.Int32 =>
      @wire.append_varint(buf, value.int().reinterpret_as_uint64())
    @reflect.Int64 =>
      @wire.append_varint(buf, value.int().reinterpret_as_uint64())
    @reflect.Uint32 => @wire.append_varint(buf, value.uint())
    @reflect.Uint64 => @wire.append_varint(buf, value.uint())
    @reflect.Enum =>
      @wire.append_varint(
        buf,
        value.enum_number().to_int64().reinterpret_as_uint64(),
      )
    @reflect.Sint32 =>
      @wire.append_varint(buf, @wire.encode_zigzag(value.int()))
    @reflect.Sint64 =>
      @wire.append_varint(buf, @wire.encode_zigzag(value.int()))
    @reflect.Fixed32 => @wire.append_fixed32(buf, value.uint().to_uint())
    @reflect.Sfixed32 =>
      @wire.append_fixed32(buf, value.int().to_int().reinterpret_as_uint())
    @reflect.Fixed64 => @wire.append_fixed64(buf, value.uint())
    @reflect.Sfixed64 =>
      @wire.append_fixed64(buf, value.int().reinterpret_as_uint64())
    @reflect.Float =>
      match value {
        @reflect.Float(f) => @wire.append_fixed32(buf, f.reinterpret_as_uint())
        _ => ()
      }
    @reflect.Double =>
      @wire.append_fixed64(buf, value.float().reinterpret_as_uint64())
    _ => ()
  }
}

// -- decoding ---------------------------------------------------------------

///|
fn decode_message(
  message : &@reflect.Message,
  bytes : BytesView,
  start : Int32,
  end : Int32,
  depth : Int32,
  opts : UnmarshalOptions,
) -> Unit raise Refused {
  if depth > opts.recursion_limit {
    raise Recursion(opts.recursion_limit)
  }
  let desc = message.descriptor()
  let mut at = start
  let unknown = Buffer()
  let mut has_unknown = false
  while at < end {
    let (number, wire_type, next) = @wire.consume_tag(bytes, at~, limit=end) catch {
      err => raise Wire(err)
    }
    if wire_type == @wire.EndGroup {
      raise Wire(@wire.Malformed(at, number, 0))
    }
    match field_lookup(message, desc, number) {
      None => {
        let after = @wire.skip_field(bytes, at~, limit=end) catch {
          err => raise Wire(err)
        }
        if !opts.discard_unknown {
          unknown.write_bytes(bytes.exact_view(start=at, end=after))
          has_unknown = true
        }
        at = after
      }
      Some(field) =>
        at = decode_field(
          message, field, bytes, wire_type, next, end, depth, opts,
        )
    }
  }
  if has_unknown {
    let existing = message.get_unknown().bytes()
    let joined = Buffer()
    joined.write_bytes(existing)
    joined.write_bytes(unknown.to_bytes())
    message.set_unknown(@reflect.RawFields::from_bytes(joined.to_bytes()))
  }
}

///|
/// The declared field, or the registered extension declared for this message
/// with that number. An extension's descriptor is not in `desc.fields`.
fn field_lookup(
  message : &@reflect.Message,
  desc : @reflect.MessageDescriptor,
  number : Int32,
) -> @reflect.FieldDescriptor? {
  match desc.field_by_number(number) {
    Some(field) => Some(field)
    None =>
      match
        @reflect.global_types.find_extension_by_number(desc.full_name, number) {
        Some(extension) => {
          let field = extension.descriptor()
          // An extension is registered for the message it extends, but a
          // message may also be a group's body, whose name differs.
          if field.is_extension {
            Some(field)
          } else {
            let _ = message
            None
          }
        }
        None => None
      }
  }
}

///|
fn decode_field(
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  bytes : BytesView,
  wire_type : @wire.WireType,
  at : Int32,
  end : Int32,
  depth : Int32,
  opts : UnmarshalOptions,
) -> Int32 raise Refused {
  if field.is_map {
    check_wire(field, wire_type, @wire.LengthDelimited)
    let (body, next) = @wire.consume_bytes(bytes, at~, limit=end) catch {
      err => raise Wire(err)
    }
    decode_map_entry(message, field, body, depth, opts)
    return next
  }
  // A numeric field accepts a packed payload whether or not its schema says
  // `packed`: proto2 senders may still choose the shorter encoding.
  let packed_shape = field.kind.is_numeric() &&
    wire_type == @wire.LengthDelimited
  if field.is_list() {
    if packed_shape {
      let (body, next) = @wire.consume_bytes(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      let list = message.mutable(field).list()
      let mut inner = 0
      while inner < body.length() {
        let (value, after) = decode_scalar(
          field,
          body,
          inner,
          body.length(),
          depth,
          opts,
        )
        list.append(value)
        inner = after
      }
      return next
    }
    check_wire(field, wire_type, expected_wire(field))
    let (value, next) = decode_value(
      field, wire_type, bytes, at, end, depth, opts,
    )
    message.mutable(field).list().append(value)
    return next
  }
  // A singular numeric field with a packed payload takes the last element,
  // which is what every implementation does for a repeated occurrence.
  if packed_shape {
    let (body, next) = @wire.consume_bytes(bytes, at~, limit=end) catch {
      err => raise Wire(err)
    }
    let mut inner = 0
    let mut last : @reflect.Value? = None
    while inner < body.length() {
      let (value, after) = decode_scalar(
        field,
        body,
        inner,
        body.length(),
        depth,
        opts,
      )
      last = Some(value)
      inner = after
    }
    match last {
      Some(value) => message.set(field, value)
      None => ()
    }
    return next
  }
  check_wire(field, wire_type, expected_wire(field))
  if field.kind.is_message() {
    if wire_type == @wire.StartGroup {
      let (body, next) = @wire.consume_group(
        bytes,
        field.number,
        at~,
        limit=end,
      ) catch {
        err => raise Wire(err)
      }
      let target = message.mutable(field).message()
      decode_message(target, body, 0, body.length(), depth + 1, opts)
      return next
    }
    let (body, next) = @wire.consume_bytes(bytes, at~, limit=end) catch {
      err => raise Wire(err)
    }
    let target = message.mutable(field).message()
    decode_message(target, body, 0, body.length(), depth + 1, opts)
    return next
  }
  let (value, next) = decode_value(
    field, wire_type, bytes, at, end, depth, opts,
  )
  message.set(field, value)
  next
}

///|
/// A field's declared wire type. A tag carrying a different one is malformed
/// rather than an invitation to reinterpret the bytes.
fn expected_wire(field : @reflect.FieldDescriptor) -> @wire.WireType {
  match field.kind {
    @reflect.String | @reflect.Bytes | @reflect.Message => @wire.LengthDelimited
    @reflect.Group => @wire.StartGroup
    @reflect.Double | @reflect.Fixed64 | @reflect.Sfixed64 => @wire.Fixed64
    @reflect.Float | @reflect.Fixed32 | @reflect.Sfixed32 => @wire.Fixed32
    _ => @wire.Varint
  }
}

///|
fn check_wire(
  field : @reflect.FieldDescriptor,
  got : @wire.WireType,
  want : @wire.WireType,
) -> Unit raise Refused {
  if got != want {
    raise Mismatch(field.full_name)
  }
}

///|
fn decode_map_entry(
  message : &@reflect.Message,
  field : @reflect.FieldDescriptor,
  body : BytesView,
  depth : Int32,
  opts : UnmarshalOptions,
) -> Unit raise Refused {
  let key_field = match field.map_key_field {
    Some(key) => key
    None => return
  }
  let value_field = match field.map_value_field {
    Some(value) => value
    None => return
  }
  let mut key : @reflect.Value = @reflect.default_for(key_field)
  let mut value : @reflect.Value = @reflect.new_field_value(value_field)
  let mut at = 0
  while at < body.length() {
    let (number, wire_type, next) = @wire.consume_tag(
      body,
      at~,
      limit=body.length(),
    ) catch {
      err => raise Wire(err)
    }
    if number == key_field.number {
      let (parsed, after) = decode_value(
        key_field,
        wire_type,
        body,
        next,
        body.length(),
        depth,
        opts,
      )
      key = parsed
      at = after
    } else if number == value_field.number {
      if value_field.kind.is_message() && value_field.kind != @reflect.Group {
        let (inner, after) = @wire.consume_bytes(
          body,
          at=next,
          limit=body.length(),
        ) catch {
          err => raise Wire(err)
        }
        let target = value.message()
        decode_message(target, inner, 0, inner.length(), depth + 1, opts)
        at = after
      } else {
        let (parsed, after) = decode_value(
          value_field,
          wire_type,
          body,
          next,
          body.length(),
          depth,
          opts,
        )
        value = parsed
        at = after
      }
    } else {
      at = @wire.skip_field(body, at~, limit=body.length()) catch {
        err => raise Wire(err)
      }
    }
  }
  match key.map_key() {
    Some(map_key) => message.mutable(field).map().set(map_key, value)
    None => ()
  }
}

///|
fn decode_value(
  field : @reflect.FieldDescriptor,
  _wire_type : @wire.WireType,
  bytes : BytesView,
  at : Int32,
  end : Int32,
  depth : Int32,
  opts : UnmarshalOptions,
) -> (@reflect.Value, Int32) raise Refused {
  match field.kind {
    @reflect.String => {
      let (text, next) = @wire.consume_string(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (String(text), next)
    }
    @reflect.Bytes => {
      let (body, next) = @wire.consume_bytes(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Bytes(body.to_owned()), next)
    }
    @reflect.Message | @reflect.Group => {
      let (body, next) = @wire.consume_bytes(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      let value = @reflect.new_element_value(field.kind, field.message_type)
      let target = value.message()
      decode_message(target, body, 0, body.length(), depth + 1, opts)
      (value, next)
    }
    _ => decode_scalar(field, bytes, at, end, depth, opts)
  }
}

///|
fn decode_scalar(
  field : @reflect.FieldDescriptor,
  bytes : BytesView,
  at : Int32,
  end : Int32,
  depth : Int32,
  opts : UnmarshalOptions,
) -> (@reflect.Value, Int32) raise Refused {
  let _ = depth
  let _ = opts
  match field.kind {
    @reflect.Bool => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Bool(@wire.decode_bool(v)), next)
    }
    @reflect.Int32 => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Int32(v.to_int()), next)
    }
    @reflect.Int64 => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Int64(v.reinterpret_as_int64()), next)
    }
    @reflect.Uint32 => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Uint32(v.to_uint()), next)
    }
    @reflect.Uint64 => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Uint64(v), next)
    }
    @reflect.Enum => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Enum(v.to_int()), next)
    }
    @reflect.Sint32 => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Int32(@wire.decode_zigzag(v & 0xFFFF_FFFFUL).to_int()), next)
    }
    @reflect.Sint64 => {
      let (v, next) = @wire.consume_varint(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Int64(@wire.decode_zigzag(v)), next)
    }
    @reflect.Fixed32 => {
      let (v, next) = @wire.consume_fixed32(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Uint32(v), next)
    }
    @reflect.Sfixed32 => {
      let (v, next) = @wire.consume_fixed32(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Int32(v.reinterpret_as_int()), next)
    }
    @reflect.Float => {
      let (v, next) = @wire.consume_fixed32(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Float(@float.Float::reinterpret_from_uint(v)), next)
    }
    @reflect.Fixed64 => {
      let (v, next) = @wire.consume_fixed64(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Uint64(v), next)
    }
    @reflect.Sfixed64 => {
      let (v, next) = @wire.consume_fixed64(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Int64(v.reinterpret_as_int64()), next)
    }
    @reflect.Double => {
      let (v, next) = @wire.consume_fixed64(bytes, at~, limit=end) catch {
        err => raise Wire(err)
      }
      (Double(v.reinterpret_as_double()), next)
    }
    _ => raise Mismatch(field.name)
  }
}

// -- extensions -------------------------------------------------------------

///|
/// Whether the message carries a value for `extension`. An extension is a field
/// with a flag, so it is read and written through the same path as a declared
/// field and only its descriptor's origin differs.
pub fn[M : @reflect.Message] has_extension(
  message : M,
  extension : &@reflect.ExtensionType,
) -> Bool {
  let field = extension.descriptor()
  message.has(field)
}

///|
/// The value of `extension`, or `None` when the message does not carry one.
pub fn[M : @reflect.Message] get_extension(
  message : M,
  extension : &@reflect.ExtensionType,
) -> @reflect.Value? {
  let field = extension.descriptor()
  if message.has(field) {
    Some(message.get(field))
  } else {
    None
  }
}

///|
/// Give `extension` a value. The value must be of the extension's kind; the
/// encoder writes it where the extension's number says.
pub fn[M : @reflect.Message] set_extension(
  message : M,
  extension : &@reflect.ExtensionType,
  value : @reflect.Value,
) -> Unit {
  message.set(extension.descriptor(), value)
}

///|
/// Drop the value of `extension`, leaving the message as if it was never set.
pub fn[M : @reflect.Message] clear_extension(
  message : M,
  extension : &@reflect.ExtensionType,
) -> Unit {
  message.clear(extension.descriptor())
}

///|
/// Visit every extension the message carries, in the order they were first set.
/// Returning `false` stops the walk.
pub fn[M : @reflect.Message] range_extensions(
  message : M,
  f : (&@reflect.ExtensionType, @reflect.Value) -> Bool,
) -> Unit {
  let desc = message.descriptor()
  let mut keep_going = true
  message.range_extensions(fn(field, value) {
    if !field.is_extension {
      return true
    }
    match @reflect.global_types.find_extension_by_name(field.full_name) {
      Some(extension) => if !f(extension, value) { keep_going = false }
      None => ()
    }
    keep_going
  })
  let _ = desc
}
