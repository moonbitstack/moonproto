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
let back = @dynamic.Message::new(descriptor)
@proto.decode(bytes, back) catch { _ => abort("decode failed") }
```

## Move between JSON and binary

`json.encode` and `json.decode` take the same reflective message. Well-known
types need their descriptors registered once:

```mbt
@known.register_all()
let text = @json.encode(message) catch { _ => abort("bad JSON output") }
let from_json = @dynamic.Message::new(descriptor)
@json.decode(text, from_json) catch { _ => abort("bad JSON input") }
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
from `T?` to `T`.

## Rules that catch people out

- 64-bit integers are strings in JSON, both on input and output. An unquoted
  64-bit literal is accepted on input but is not what the encoder emits; use the
  original text when exact digits matter.
- Unknown fields are kept on the message and re-emitted by the next encode.
  `proto.reset` deliberately clears them.
- Proto3 scalars without presence are omitted from JSON output when they hold
  their zero value, even if the input mentioned them. Set
  `emit_default_values` in the marshal options to force them out.
- Enum names in JSON and text need the enum's file descriptor in
  `reflect.global_files`. Register well-known types with `@known.register_all()`
  before using `Any`, `Timestamp`, `Duration`, `FieldMask` or `Struct`.
- A `FieldMask` path is lowerCamelCase in JSON and snake_case in the message.
  Underscores are not valid in its JSON form.
- Only one member of a oneof may be set per JSON object. On the binary wire the
  last member wins.
- Generated struct fields are private to their package. Code in another package
  must use the generated accessors or the `reflect.Message` trait.
