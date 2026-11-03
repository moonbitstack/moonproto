///|
/// The framing the conformance runner expects: a 4-byte little-endian length,
/// then that many bytes of `ConformanceRequest`, repeated until the input ends.
async fn main {
  @conformance.register_test_types()
  @conformance.register_known_types()
  let input = Buffer()
  while true {
    match @stdio.stdin.read_some() {
      Some(chunk) => input.write_bytes(chunk)
      None => break
    }
  }
  let bytes = input.to_bytes()
  let output = Buffer()
  let mut at = 0
  while at + 4 <= bytes.length() {
    let size = length_at(bytes, at)
    let start = at + 4
    let end = start + size
    if end > bytes.length() {
      break
    }
    let request = bytes.exact_view(start~, end~).to_owned()
    let response = @conformance.handle(request)
    write_length(output, response.length())
    output.write_bytes(response)
    at = end
  }
  let result = output.to_bytes()
  let mut written = 0
  while written < result.length() {
    let count = @stdio.stdout.write_once(
      result,
      offset=written,
      len=result.length() - written,
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
