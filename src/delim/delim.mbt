// A varint length followed by the message body, repeated for as many messages
// as the stream carries.

///|
pub(open) trait Writer {
  fn write(Self, BytesView) -> Unit raise Refused
}

///|
pub(open) trait Reader {
  fn read_byte(Self) -> Int32?
}

///|
pub(all) struct MarshalOptions {
  marshal : @proto.MarshalOptions
}

///|
pub let marshal_options : MarshalOptions = { marshal: @proto.marshal_options, }

///|
pub(all) struct UnmarshalOptions {
  unmarshal : @proto.UnmarshalOptions
  max_size : Int32
}

///|
pub let unmarshal_options : UnmarshalOptions = {
  unmarshal: @proto.unmarshal_options,
  max_size: 4 << 20,
}

///|
pub(all) suberror Refused {
  Wire(@wire.Refused)
  Proto(@proto.Refused)
  Size(Int32, Int32)
  Truncated
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Wire(_) => logger.write_string("wire error")
    Proto(_) => logger.write_string("message error")
    Size(got, limit) =>
      logger.write_string(
        "message size " + got.to_string() + " exceeds " + limit.to_string(),
      )
    Truncated => logger.write_string("stream ended inside a message")
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// Write one size-delimited message, returning the bytes written.
pub fn[M : @reflect.Message] encode_to(
  writer : &Writer,
  message : M,
  marshal_options~ : MarshalOptions = marshal_options,
) -> Int32 raise Refused {
  let body = @proto.encode(message, marshal_options=marshal_options.marshal) catch {
    err => raise Proto(err)
  }
  let prefix = Buffer()
  @wire.append_varint(prefix, body.length().to_uint64())
  let head = prefix.to_bytes()
  writer.write(head)
  writer.write(body)
  head.length() + body.length()
}

///|
/// Read one size-delimited message into `message`.
pub fn[M : @reflect.Message] decode_from(
  reader : &Reader,
  message : M,
  unmarshal_options~ : UnmarshalOptions = unmarshal_options,
) -> Unit raise Refused {
  let limit = if unmarshal_options.max_size == 0 {
    4 << 20
  } else {
    unmarshal_options.max_size
  }
  let mut length = 0UL
  let mut shift = 0
  let mut done = false
  let mut count = 0
  while !done {
    if count >= 10 {
      raise Wire(@wire.Refused::Overflow(count))
    }
    let byte = match reader.read_byte() {
      Some(value) => value
      None => raise Truncated
    }
    length = length | ((byte.to_uint64() & 0x7FUL) << shift)
    if byte < 0x80 {
      done = true
    } else {
      shift = shift + 7
      count = count + 1
    }
  }
  if limit > 0 && length > limit.to_uint64() {
    raise Size(length.to_int(), limit)
  }
  let size = length.to_int()
  let body = Buffer()
  let mut i = 0
  while i < size {
    match reader.read_byte() {
      Some(value) => body.write_byte(value.to_byte())
      None => raise Truncated
    }
    i = i + 1
  }
  @proto.decode(
    body.to_bytes(),
    message,
    unmarshal_options=unmarshal_options.unmarshal,
  ) catch {
    err => raise Proto(err)
  }
}

///|
/// A writer that collects into a buffer, for callers that already hold bytes.
pub struct BytesWriter {
  buf : Buffer
}

///|
pub fn BytesWriter::new() -> BytesWriter {
  { buf: Buffer(), }
}

///|
pub fn BytesWriter::to_bytes(self : BytesWriter) -> Bytes {
  self.buf.to_bytes()
}

///|
pub impl Writer for BytesWriter with fn write(self, bytes : BytesView) -> Unit raise Refused {
  self.buf.write_bytes(bytes)
}

///|
pub extend BytesWriter with Writer::{write}

///|
/// A reader over a fixed byte sequence.
pub struct BytesReader {
  bytes : Bytes
  mut pos : Int32
}

///|
pub fn BytesReader::new(bytes : Bytes) -> BytesReader {
  { bytes, pos: 0, }
}

///|
pub impl Reader for BytesReader with fn read_byte(self) -> Int32? {
  if self.pos < self.bytes.length() {
    let value = self.bytes[self.pos].to_int()
    self.pos = self.pos + 1
    Some(value)
  } else {
    None
  }
}

///|
pub extend BytesReader with Reader::{read_byte}
