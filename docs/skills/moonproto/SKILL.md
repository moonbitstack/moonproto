---
name: moonproto
description: Encode, decode and generate Protocol Buffers messages in MoonBit. Use when a task needs protobuf binary, JSON or text serialization, parsing .proto schemas, protoc code generation, well-known types, or reflective message handling.
---

# moonproto

Install with `moon add moonbitstack/moonproto` and import only the packages
you need:

<!-- nocheck -->
```mbt
import {
  "moonbitstack/moonproto/desc",
  "moonbitstack/moonproto/dynamic",
  "moonbitstack/moonproto/json",
  "moonbitstack/moonproto/known",
  "moonbitstack/moonproto/parser",
  "moonbitstack/moonproto/proto",
  "moonbitstack/moonproto/reflect",
}
```

## Work with a schema without generating code

Parse a `.proto` source, build a runtime descriptor and fill a dynamic message.
Every encoder works on `reflect.Message`, so the same code path serves generated
structs:

```mbt
let source =
  "syntax = \"proto3\";\n" +
  "package hello;\n" +
  "message Request { string name = 1; int32 count = 2; }\n"
let parsed = @parser.parse("hello.proto", source) catch {
  _ => abort("bad schema")
}
let built = @desc.build_file(parsed) catch { _ => abort("bad descriptor") }
let descriptor = built.messages[0]
let message = @dynamic.Message::new(descriptor)
let name = descriptor.field_by_name("name").unwrap()
message.set(name, @reflect.String("moon"))
let bytes = @proto.encode(message) catch { _ => abort("encode failed") }
assert_eq(bytes.length(), 6)
let back = @dynamic.Message::new(descriptor)
@proto.decode(bytes, back) catch { _ => abort("decode failed") }
assert_eq(back.get(name).string(), "moon")
```

## Move between JSON and binary

`json.encode` and `json.decode` take the same reflective message. Well-known
types need their descriptors registered once:

```mbt
@known.register_all()
let text = @json.encode(message) catch { _ => abort("bad JSON output") }
assert_eq(text, "{\"name\":\"moon\"}")
let from_json = @dynamic.Message::new(descriptor)
@json.decode(text, from_json) catch { _ => abort("bad JSON input") }
assert_eq(from_json.get(name).string(), "moon")
```

## Ask whether a field is set

`Message::has` answers with the same rule the encoders use, so it is what tells
"the peer sent a zero" from "the peer sent nothing":

```mbt
assert_eq(message.has(name), true)
let count = descriptor.field_by_name("count").unwrap()
message.set(count, @reflect.Int32(0))
assert_eq(message.has(count), false)
assert_eq(@proto.encode(message).length(), 6)
```

## Generate real MoonBit structs

`protoc-gen-mbt` turns a schema into a struct whose fields are the protobuf
fields. Repeated fields become `Array[T]`, maps become `Map[K, V]`, and a oneof
becomes an enum. The generated file also implements `reflect.Message`:

```sh
protoc -I . --plugin=protoc-gen-mbt=path/to/protoc-gen-mbt \
  --mbt_out=src hello.proto
```

The generated package needs `desc`, `json`, `proto` and `reflect` imported in
its `moon.pkg`. Read and write fields through the generated accessors
(`Request::name`, `Request::set_name`, `Request::counts`) rather than by
reaching into the struct from another package.

`edition = "2023"` and `edition = "2024"` are supported. Features are resolved
from the innermost declaration outward, so a file-level
`option features.field_presence = IMPLICIT` changes the generated field types
from `T?` to `T`. A proto3 field needs the `optional` keyword to get `T?`; a
field written without a label holds a plain `T`.

## Rules that catch people out

- 64-bit integers are strings in JSON, both on input and output. An unquoted
  64-bit literal is accepted on input but is not what the encoder emits; use the
  original text when exact digits matter.
- Repeated scalars: proto3 packs by default, proto2 does not. An explicit
  `[packed = true]` in proto2 writes one length-delimited run, and
  `[packed = false]` (or `features.repeated_field_encoding = EXPANDED`) repeats
  the tag per element.
- A field is named once per JSON object. Two members reaching one field — the
  JSON name and the declared name — and the same member name written twice are
  both refused, so a document that duplicates a key is an error rather than a
  silent overwrite.
- Bytes are base64: either the standard or the URL-safe alphabet on input, with
  or without padding. The encoder always writes the standard alphabet, padded.
- Unknown fields are kept on the message and re-emitted by the next encode.
  `proto.reset` deliberately clears them.
- A proto3 scalar without presence has no set state: binary and JSON both leave
  it out when it holds the zero of its kind, even if the code or the input
  mentioned it, and `Message::has` reports it as not set. Write `optional` in
  the schema when a zero has to survive, and set `emit_default_values` in the
  JSON marshal options to force every field into the document.
- Negative zero is a value, not a zero. A float or double field holding `-0.0`
  is written in binary and JSON (`-0`) and reads back with its sign; every other
  kind's zero is compared by value.
- Reading a message whose bytes carry an explicit zero stores the value but not
  the presence: re-encoding drops the field, which is what a peer expects.
- Enum names in JSON and text need the enum's file descriptor in
  `reflect.global_files`; without it the encoder writes the number. Register a
  schema read by `parser` with `reflect.global_files.register(file)`, and the
  well-known types with `@known.register_all()`, before using `Any`,
  `Timestamp`, `Duration`, `FieldMask` or `Struct`.
- A `FieldMask` is one comma-separated string in JSON, and each path is
  lowerCamelCase there and snake_case in the message: `"userName"` reads as
  `user_name` and writes back as `"userName"`. An underscore or a space in the
  JSON form is refused.
- Only one member of a oneof may be set per JSON object. On the binary wire the
  last member wins.
- Generated struct fields are private to their package. Code in another package
  must use the generated accessors or the `reflect.Message` trait.
- A received message may nest up to `recursion_limit` deep (10 000 by default);
  lower it in the unmarshal options to stop a hostile message early.
