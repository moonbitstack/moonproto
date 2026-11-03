# API inventory: what the reference has, and where each thing goes

Every public capability of the reference implementation is listed here once,
grouped by the package it was read from. Internal packages whose only job is to
support a mechanism that does not exist here are listed with a `drop:` reason,
so the absence is a decision rather than an omission.

The list was read from source, not from memory. The version checked out while
writing it:

| Library | Version | Licence | Read from |
|:--|:--|:--|:--|
| protobuf-go | v1.36.12 | BSD-3-Clause | the repository root |

## Reading the tables

`Home` is one of three things:

- a package of this library — `wire`, `reflect`, `desc`, `proto`, `json`,
  `text`, `delim`, `dynamic`, `known/*`, `gen`, `cmd/protoc-gen-mbt`;
- `core: X` — MoonBit core already has it, under that name;
- `drop: <reason>` — not built, with the reason in one clause.

`Cost` is the cost of the operation the row is about; `O(1)*` is amortised.
Rows that bundle a family of names state the cost of the operation the family is
used for.

## `proto`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| proto | `Message` (alias of `protoreflect.ProtoMessage`) | the top-level message interface | — | reflect: `Message` |
| proto | `Error` | sentinel matched by every error the module produces | — | proto: `Refused` (one per package) |
| proto | `MessageName` | full name of a message | O(1) | proto: `Message::descriptor().full_name()` |
| proto | `Marshal` / `MarshalOptions` | binary encode; `AllowPartial`, `Deterministic`, `UseCachedSize` | O(size) | proto: `encode` / `encode_to` |
| proto | `Unmarshal` / `UnmarshalOptions` | binary decode; `Merge`, `AllowPartial`, `DiscardUnknown`, `Resolver`, `RecursionLimit`, `NoLazyDecoding` | O(size) | proto: `decode` |
| proto | `Merge` | merge one message into another | O(size) | proto: `merge` |
| proto | `Clone` / `CloneOf` | deep copy | O(size) | proto: `clone` |
| proto | `Equal` | semantic equality | O(size) | proto: `equal` |
| proto | `Size` | encoded size without encoding | O(size) | proto: `size` |
| proto | `Reset` | clear every field | O(size) | proto: `reset` |
| proto | `CheckInitialized` | refuse missing required fields | O(size) | proto: `check_initialized` |
| proto | `HasExtension` / `GetExtension` / `SetExtension` / `ClearExtension` / `RangeExtensions` | extension access by type | O(1) / O(k) | proto: same names |
| proto | `Bool` … `String` wrappers | pointer-to-scalar helpers | O(1) | drop: MoonBit has no `*T`; optional fields are `T?` |

## `encoding/protowire`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protowire | `Number` | field number, 1…2^29-1 | — | wire: `FieldNumber` |
| protowire | `Type` | wire type 0–5 | — | wire: `WireType` |
| protowire | `ParseError` | decode a negative return into an error | O(1) | wire: `Refused` variants |
| protowire | `ConsumeField` / `ConsumeFieldValue` | skip a whole field | O(n) | wire: `skip_field` |
| protowire | `AppendTag` / `ConsumeTag` / `SizeTag` | tag encode, decode, measure | O(1) | wire: `append_tag` / `consume_tag` / `size_tag` |
| protowire | `AppendVarint` / `ConsumeVarint` / `SizeVarint` | base-128 | O(1) | wire: `append_varint` / `consume_varint` / `size_varint` |
| protowire | `AppendFixed32` / `ConsumeFixed32` / `SizeFixed32` and the 64-bit trio | little-endian fixed width | O(1) | wire: same names |
| protowire | `AppendBytes` / `ConsumeBytes` / `SizeBytes` | length-delimited bytes | O(1) / O(n) | wire: same names |
| protowire | `AppendString` / `ConsumeString` | length-delimited UTF-8 | O(1) / O(n) | wire: same names |
| protowire | `AppendGroup` / `ConsumeGroup` / `SizeGroup` | start/end group | O(n) | wire: same names |
| protowire | `DecodeTag` / `EncodeTag` | tag as one integer | O(1) | wire: `decode_tag` / `encode_tag` |
| protowire | `DecodeZigZag` / `EncodeZigZag` | signed varint | O(1) | wire: same names |
| protowire | `DecodeBool` / `EncodeBool` | zero/non-zero | O(1) | wire: same names |

## `reflect/protoreflect`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protoreflect | `Descriptor` | common descriptor accessors | O(1) | reflect: `Descriptor` |
| protoreflect | `FileDescriptor` | a file's declarations, imports, source locations | O(1) | reflect: `FileDescriptor` |
| protoreflect | `MessageDescriptor` | fields, oneofs, nested types, reserved and extension ranges | O(1) | reflect: `MessageDescriptor` |
| protoreflect | `FieldDescriptor` | number, kind, cardinality, presence, default, map key/value, containing type | O(1) | reflect: `FieldDescriptor` |
| protoreflect | `OneofDescriptor` | members of a oneof, synthetic flag | O(1) | reflect: `OneofDescriptor` |
| protoreflect | `ExtensionDescriptor` / `ExtensionTypeDescriptor` | an extension field and its concrete type | O(1) | reflect: same names |
| protoreflect | `EnumDescriptor` / `EnumValueDescriptor` | values, reserved names and ranges, closedness | O(1) | reflect: same names |
| protoreflect | `ServiceDescriptor` / `MethodDescriptor` | methods, input/output, streaming flags | O(1) | reflect: same names |
| protoreflect | `FileImports` / `FileImport` | imports with `IsPublic` | O(1) | reflect: same names |
| protoreflect | `MessageDescriptors`, `FieldDescriptors`, `OneofDescriptors`, `ExtensionDescriptors`, `EnumDescriptors`, `EnumValueDescriptors`, `ServiceDescriptors`, `MethodDescriptors` | indexed and by-name lookup | O(1) / O(n) | reflect: same names |
| protoreflect | `Names`, `FieldNumbers`, `FieldRanges`, `EnumRanges` | reserved sets and ranges | O(1) / O(n) | reflect: same names |
| protoreflect | `Value` | the tagged union of every field value | O(1) | reflect: `Value` |
| protoreflect | `MapKey` | the six key kinds | O(1) | reflect: `MapKey` |
| protoreflect | `RawFields` | unknown fields, validated on demand | O(n) | reflect: `RawFields` |
| protoreflect | `Message` | reflective read/write of a message | O(1) per field | reflect: `Message` |
| protoreflect | `MessageType` | construct and describe a message type | O(1) | reflect: `MessageType` |
| protoreflect | `Enum` / `EnumType` | an enum value and its type | O(1) | reflect: same names |
| protoreflect | `List` / `Map` | repeated and map field views | O(1) / O(n) | reflect: same names |
| protoreflect | `ExtensionType` | an extension's concrete type and validation | O(1) | reflect: `ExtensionType` |
| protoreflect | `Syntax` | proto2 / proto3 / editions | O(1) | reflect: `Syntax` |
| protoreflect | `Cardinality` | optional / required / repeated | O(1) | reflect: `Cardinality` |
| protoreflect | `Kind` | the 18 field kinds | O(1) | reflect: `Kind` |
| protoreflect | `Name` / `FullName` | identifiers and qualified names | O(1) / O(n) | reflect: same names |
| protoreflect | `FieldNumber` / `EnumNumber` | numeric identities | O(1) | reflect: same names |
| protoreflect | `SourceLocations` / `SourceLocation` / `SourcePath` | positions and comments | O(1) / O(n) | reflect: same names |
| protoreflect | `doNotImplement` | seals the interfaces | — | drop: `pub(open) trait` is implemented outside the package on purpose; sealing is not possible and not wanted |

## `reflect/protoregistry`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protoregistry | `Files` | registry of file descriptors, by path and by qualified name | O(1)* | reflect: `Files` |
| protoregistry | `Types` | registry of message, enum and extension types | O(1)* | reflect: `Types` |
| protoregistry | `GlobalFiles` / `GlobalTypes` | the process-wide registries | — | reflect: `global_files` / `global_types` |
| protoregistry | `MessageTypeResolver` / `ExtensionTypeResolver` | the lookup halves of `Types` | — | reflect: `Resolver` and the `Types` methods |
| protoregistry | `NotFound` | a lookup miss | — | drop: lookups return `Option`; a miss is not an error |

## `reflect/protodesc`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protodesc | `NewFile` / `NewFiles` / `FileOptions` | build runtime descriptors from `FileDescriptorProto`; `AllowUnresolvable` | O(n) | desc: `build_file` / `build_files` / `FileOptions` |
| protodesc | `Resolver` | file and declaration lookup while building | — | desc: `Resolver` |
| protodesc | `ToFileDescriptorProto` | runtime descriptors back to the proto message | O(n) | desc: `to_file_descriptor_proto` |
| protodesc | `ToDescriptorProto`, `ToFieldDescriptorProto`, `ToOneofDescriptorProto`, `ToEnumDescriptorProto`, `ToEnumValueDescriptorProto`, `ToServiceDescriptorProto`, `ToMethodDescriptorProto` | the per-declaration converters | O(n) | desc: same names |

## `encoding/protojson`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protojson | `Marshal` / `MarshalOptions` | JSON encode; `Multiline`, `Indent`, `AllowPartial`, `UseProtoNames`, `UseEnumNumbers`, `EmitUnpopulated`, `EmitDefaultValues`, `Resolver` | O(size) | json: `encode` |
| protojson | `Unmarshal` / `UnmarshalOptions` | JSON decode; `AllowPartial`, `DiscardUnknown`, `Resolver`, `RecursionLimit` | O(size) | json: `decode` |
| protojson | `Format` | debug output, unstable | O(size) | json: `format` |
| protojson | the well-known type forms | `Any`, `Timestamp`, `Duration`, `Struct`, `Value`, `ListValue`, wrappers, `FieldMask`, `Empty` | O(size) | json: recognised by full name |
| protojson | 64-bit integers as strings, enums by name, `null` for absent | the mapping rules | O(1) | json: in the encoder and decoder |

## `encoding/prototext`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| prototext | `Marshal` / `MarshalOptions` | text encode; `Multiline`, `Indent`, `EmitASCII`, `AllowPartial`, `EmitUnknown`, `Resolver` | O(size) | text: `encode` |
| prototext | `Unmarshal` / `UnmarshalOptions` | text decode; `AllowPartial`, `DiscardUnknown`, `Resolver`, `RecursionLimit` | O(size) | text: `decode` |
| prototext | `Format` | debug output, unstable | O(size) | text: `format` |
| prototext | `Any` expansion, groups, extensions in brackets | the text rules | O(1) | text: in the encoder and decoder |

## `encoding/protodelim`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protodelim | `MarshalTo` / `MarshalOptions` | varint size prefix plus message | O(size) | delim: `encode_to` |
| protodelim | `UnmarshalFrom` / `UnmarshalOptions` | read the prefix, then the message; `MaxSize` | O(size) | delim: `decode_from` |
| protodelim | `SizeTooLargeError` | the prefix exceeded `MaxSize` | — | delim: `Refused::Size` |
| protodelim | `Reader` | `Read` plus `ReadByte` | — | delim: `Reader` |

## `types/dynamicpb`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| dynamicpb | `NewMessage` | a message driven by a descriptor | O(1) | dynamic: `Message::new` |
| dynamicpb | `NewMessageType` | a `MessageType` for a descriptor | O(1) | dynamic: `new_message_type` |
| dynamicpb | `NewEnumType` | an `EnumType` for a descriptor | O(1) | dynamic: `new_enum_type` |
| dynamicpb | `NewExtensionType` | an `ExtensionType` for a descriptor | O(1) | dynamic: `new_extension_type` |
| dynamicpb | `Types` | the four lookups over a `Files` | O(1) | dynamic: `Types` |

## `types/known`, `types/descriptorpb`, `types/pluginpb`, `types/gofeaturespb`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| known | `anypb`, `apipb`, `durationpb`, `emptypb`, `fieldmaskpb`, `sourcecontextpb`, `structpb`, `timestamppb`, `typepb`, `wrapperspb` | the well-known messages | O(1) | known: one package each |
| descriptorpb | `descriptor.proto` messages | `FileDescriptorProto` and the rest, including `FeatureSet` and `FeatureSetDefaults` | O(1) | known: `known/descriptor` |
| pluginpb | `plugin.proto` messages | `CodeGeneratorRequest`, `CodeGeneratorResponse`, `Version` | O(1) | known: `known/plugin` |
| gofeaturespb | `go_features.proto` and edition defaults | the feature messages this module reads | O(1) | known: `known/features` |

## `compiler/protogen`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protogen | `Options` | `ParamFunc`, `ImportRewriteFunc`, `FeatureSetDefaults`, `StripForEditionsDiff`, `DefaultAPILevel` | O(1) | gen: `Options` |
| protogen | `Options.Run` / `Options.New` | the plugin entry point and its constructor | O(n) | gen: `run` / `new_plugin` |
| protogen | `Plugin` | request, files, generated files, response | O(1) | gen: `Plugin` |
| protogen | `File`, `Message`, `Field`, `Oneof`, `Enum`, `EnumValue`, `Service`, `Method` | the descriptor plus the naming the generator decided | O(1) | gen: same names |
| protogen | `GeneratedFile` | `P`, `QualifiedGoIdent`, `Import`, `Skip`/`Unskip`, `Content` | O(n) | gen: `GeneratedFile`, with `p`, `qualified_ident`, `import`, `content` |
| protogen | `GoIdent`, `GoImportPath`, `GoPackageName` | identifiers and import paths | O(1) | gen: `MbtIdent`, `MbtImportPath`, package name |
| protogen | `Annotation`, `Location`, `CommentSet`, `Comments` | source positions and comments carried into generated code | O(n) | gen: `Annotation`, `Location`, `CommentSet`, `Comments` |

## `cmd/protoc-gen-go`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protoc-gen-go | the binary | reads a request, writes a response, accepts `paths`, `module`, `annotate_code` | O(n) | cmd/protoc-gen-mbt |

## `runtime/protoiface`

| Ref | Name | What it does | Cost | Home |
|:--|:--|:--|:--|:--|
| protoiface | `Methods` | optional fast paths for marshal, unmarshal, size, merge, check-initialized | — | reflect: `Methods` trait |

## Internal packages that are not ported

| Ref package | Why it exists in the reference | Decision |
|:--|:--|:--|
| `internal/impl` | reads and writes fields by `unsafe` offsets computed from struct tags; the coder machinery | **drop.** The generator emits the accessors; there are no offsets to compute. |
| `internal/filedesc` | lazily builds and caches descriptors | **drop.** `desc` builds eagerly in one pass and returns immutable values. |
| `internal/encoding/text`, `internal/encoding/json` | tokenisers shared by the text and JSON codecs | **drop as separate packages.** The tokenisers live inside `text` and `json`. |
| `internal/order` | deterministic field and map ordering | **drop as a package.** The encoder sorts in place when `deterministic` is set. |
| `internal/detrand` | stable pseudo-randomisation of defaults | **drop.** Not observable in the output this module promises; excluded deliberately. |
| `internal/genid` | reserved identifiers for generated code | **drop as a package.** The generator prefixes its own names; the list is a constant in `gen`. |
| `internal/errors` | the `proto.Error` chain | **drop.** Each package owns its `Refused`. |
| `internal/descopts` | typed accessors for descriptor options | **drop.** `Descriptor::options` returns `&Message?`; the caller couples it. |
| `internal/descfmt` | descriptor formatting for `%v` | **drop.** `Show` implementations on the descriptor traits replace it. |
| `internal/editiondefaults`, `internal/editionssupport` | compiled-in feature defaults and the supported-edition range | **fold into `known/features` and `desc`.** |
| `internal/pragma` | `DoNotImplement`, `NoUnkeyedLiterals` | **drop.** Sealing is not possible with open traits; unkeyed literals do not exist. |
| `internal/weakdeps` | weak field support | **drop.** Weak fields were removed from the protobuf language. |
| `internal/testprotos`, `internal/fuzz`, `internal/benchmarks`, `internal/conformance` | test and benchmark fixtures, conformance driver | **drop as library packages; read as test sources.** The conformance runner drives the module from outside; the fixtures become test vectors. |
