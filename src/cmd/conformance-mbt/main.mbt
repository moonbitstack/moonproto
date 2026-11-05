///|
/// The framing the conformance runner expects: a 4-byte little-endian length,
/// then that many bytes of `ConformanceRequest`. The runner waits for each
/// response before it writes the next request, so the testee answers as soon as
/// a whole frame has arrived.
async fn main {
  @conformance.register_test_types()
  @conformance.register_known_types()
  @conformance.register_official_types()
  while true {
    match read_frame(4) {
      None => break
      Some(header) => {
        let size = length_at(header, 0)
        if size < 0 || size > 67108864 {
          break
        }
        match read_frame(size) {
          None => break
          Some(request) => write_frame(@conformance.handle(request))
        }
      }
    }
  }
}

///|
async fn read_frame(size : Int32) -> Bytes? {
  let buf = Buffer()
  let mut have = 0
  while have < size {
    match @stdio.stdin.read_some(max_len=size - have) {
      Some(chunk) => {
        buf.write_bytes(chunk)
        have = have + chunk.length()
      }
      None => return None
    }
  }
  Some(buf.to_bytes())
}

///|
async fn write_frame(response : Bytes) -> Unit {
  let buf = Buffer()
  write_length(buf, response.length())
  buf.write_bytes(response)
  let bytes = buf.to_bytes()
  let mut written = 0
  while written < bytes.length() {
    let count = @stdio.stdout.write_once(
      bytes,
      offset=written,
      len=bytes.length() - written,
    )
    if count <= 0 {
      break
    }
    written = written + count
  }
}

///|
fn length_at(bytes : Bytes, at : Int32) -> Int32 {
  bytes[at].to_int() |
  (bytes[at + 1].to_int() << 8) |
  (bytes[at + 2].to_int() << 16) |
  (bytes[at + 3].to_int() << 24)
}

///|
fn write_length(buf : Buffer, size : Int32) -> Unit {
  buf.write_byte((size & 0xFF).to_byte())
  buf.write_byte(((size >> 8) & 0xFF).to_byte())
  buf.write_byte(((size >> 16) & 0xFF).to_byte())
  buf.write_byte(((size >> 24) & 0xFF).to_byte())
}
