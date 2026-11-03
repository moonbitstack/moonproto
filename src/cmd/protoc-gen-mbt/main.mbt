///|
/// Read the request protoc wrote to standard input, generate, and write the
/// response back. Standard input is drained in chunks because the async stdio
/// channel exposes a byte source rather than a length.
async fn main {
  let input = Buffer()
  while true {
    match @stdio.stdin.read_some() {
      Some(chunk) => input.write_bytes(chunk)
      None => break
    }
  }
  let response = @gen.plugin_main(input.to_bytes())
  let mut written = 0
  while written < response.length() {
    let count = @stdio.stdout.write_once(
      response,
      offset=written,
      len=response.length() - written,
    )
    if count <= 0 {
      break
    }
    written = written + count
  }
}
