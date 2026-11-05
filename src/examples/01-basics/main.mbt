// The smallest useful path through the library: schema -> descriptor ->
// dynamic message -> bytes -> message again.

///|
const SCHEMA : String = "syntax = \"proto3\";\n" +
  "package hello;\n" +
  "message Request { string name = 1; int32 count = 2; repeated int32 nums = 3; }\n"

///|
fn main {
  let parsed = @parser.parse("hello.proto", SCHEMA) catch {
    _ => abort("bad schema")
  }
  let built = @desc.build_file(parsed) catch { _ => abort("bad descriptor") }
  let descriptor = built.messages[0]

  let message = @dynamic.Message::new(descriptor)
  let name = descriptor.field_by_name("name").unwrap()
  let count = descriptor.field_by_name("count").unwrap()
  let nums = descriptor.field_by_name("nums").unwrap()
  message.set(name, @reflect.String("moon"))
  message.set(count, @reflect.Int32(150))
  let list = message.mutable(nums).list()
  list.append(@reflect.Int32(1))
  list.append(@reflect.Int32(300))

  let bytes = @proto.encode(message) catch { _ => abort("encode failed") }
  println("binary bytes: \{bytes.length()}")

  let back = @dynamic.Message::new(descriptor)
  @proto.decode(bytes, back) catch {
    _ => abort("decode failed")
  }
  println("name: \{back.get(name).string()}")
  println("count: \{back.get(count).int()}")
  println("nums: \{back.get(nums).list().length()}")
  let again = @proto.encode(back) catch { _ => abort("re-encode failed") }
  println("same bytes again: \{again == bytes}")
}
