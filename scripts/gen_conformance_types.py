#!/usr/bin/env python3
"""Turn the pinned conformance descriptor set into MoonBit descriptor records.

The official conformance runner names the messages it wants by their full proto
name. The testee registers those names as dynamic messages, but the runtime
descriptors have to exist first. This script reads the FileDescriptorSet that
protoc 36.2 produced from protobuf 36.2's conformance test schemas and emits
`src/conformance/test_types.mbt`, so `moon test` and the testee need neither
protoc nor a protobuf library at run time.

Every message gets its own `///|` segment and function: one huge literal would
exceed the compiler's text segment limit. Regenerate the input with
`scripts/vendor_conformance_descriptors.sh`, which pins the protobuf version
and the exact protoc invocation.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tests" / "conformance" / "descriptor_set.bin"
TARGET = ROOT / "src" / "conformance" / "test_types.mbt"

# FeatureSet field number -> Features record field. Zero means inherit.
FEATURE_FIELDS = {
    1: "field_presence",
    2: "enum_type",
    3: "repeated_field_encoding",
    4: "utf8_validation",
    5: "message_encoding",
    6: "json_format",
}
FEATURE_NAMES = (
    "field_presence",
    "enum_type",
    "repeated_field_encoding",
    "message_encoding",
    "utf8_validation",
    "json_format",
)
# Where the FeatureSet sits inside each options message.
OPTIONS_FEATURE_FIELD = {
    "file": 50,
    "message": 12,
    "field": 21,
    "enum": 7,
}
EDITIONS = {1000: "2023", 1001: "2024", 1002: "UNSTABLE"}
SIGN_BIT = 1 << 63
FULL_RANGE = 1 << 64


def signed(value: int) -> int:
    """A negative enum or range bound arrives as a ten-byte varint."""
    return value - FULL_RANGE if value >= SIGN_BIT else value


def read_varint(data: bytes, at: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return signed(value), at
        shift += 7


def wire_fields(data: bytes):
    """Yield (number, wire type, value) for a length-delimited message."""
    at = 0
    while at < len(data):
        tag, at = read_varint(data, at)
        number, wire = tag >> 3, tag & 7
        if wire == 0:
            value, at = read_varint(data, at)
        elif wire == 2:
            size, at = read_varint(data, at)
            value = data[at : at + size]
            at += size
        elif wire == 5:
            value = data[at : at + 4]
            at += 4
        elif wire == 1:
            value = data[at : at + 8]
            at += 8
        else:
            raise SystemExit(f"unsupported wire type {wire} in descriptor set")
        yield number, wire, value


def group(data: bytes) -> dict[int, list]:
    out: dict[int, list] = {}
    for number, _wire, value in wire_fields(data):
        out.setdefault(number, []).append(value)
    return out


def text(value: bytes) -> str:
    return value.decode("utf-8")


def one(values: dict[int, list], number: int, default=None):
    items = values.get(number)
    return items[0] if items else default


def read_features(blob: bytes | None, kind: str) -> dict[str, int]:
    out = {name: 0 for name in FEATURE_NAMES}
    if blob is None:
        return out
    number = OPTIONS_FEATURE_FIELD[kind]
    for field_number, _wire, value in wire_fields(blob):
        if field_number == number:
            for inner, _w, code in wire_fields(value):
                if inner in FEATURE_FIELDS:
                    out[FEATURE_FIELDS[inner]] = code
    # utf8_validation uses VERIFY=2/NONE=3 in descriptor.proto, while the
    # runtime record uses 1/2. Nothing reads it today, but keep it faithful.
    if out["utf8_validation"] >= 2:
        out["utf8_validation"] -= 1
    return out


def merge(parent: dict[str, int], child: dict[str, int]) -> dict[str, int]:
    return {name: child[name] or parent[name] for name in FEATURE_NAMES}


def esc(value: str) -> str:
    out = []
    for ch in value:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32:
            out.append("\\u{{{:x}}}".format(ord(ch)))
        else:
            out.append(ch)
    return "".join(out)


def opt_str(value: str | None) -> str:
    return "None" if value is None else f'Some("{esc(value)}")'


def opt_int(value: int | None) -> str:
    return "None" if value is None else f"Some({value})"


def bool_text(value: bool) -> str:
    return "true" if value else "false"


def features_text(features: dict[str, int]) -> str:
    inner = ", ".join(f"{name}: {features[name]}" for name in FEATURE_NAMES)
    return f"{{ {inner}, }}"


def array_text(items: list[str], indent: str) -> str:
    if not items:
        return "[]"
    joined = (",\n").join(indent + "  " + item for item in items)
    return "[\n" + joined + ",\n" + indent + "]"


class Emitter:
    def __init__(self) -> None:
        self.definitions: list[str] = []
        self.counter = 0

    def add(self, returns: str, body: str) -> str:
        self.counter += 1
        name = f"official_{returns}_{self.counter}"
        self.definitions.append(f"///|\nfn {name}() -> @desc.{returns} {{\n{body}\n}}\n")
        return f"{name}()"


def parse_field(data: bytes, parent: dict[str, int]) -> str:
    v = group(data)
    options = one(v, 8)
    own = merge(parent, read_features(options, "field"))
    packed_off = False
    packed_on = False
    if options is not None:
        for number, _wire, value in wire_fields(options):
            # FieldOptions.packed is the legacy spelling of the editions
            # feature: true packs the field, false expands it. Recorded as the
            # feature, the way protoc normalizes an option into an editions
            # descriptor, so one place decides how a repeated field is written.
            if number == 2:
                if value == 0:
                    packed_off = True
                else:
                    packed_on = True
    if packed_on:
        own = dict(own)
        own["repeated_field_encoding"] = 1
    return "\n".join(
        [
            "{",
            f'  name: "{esc(text(one(v, 1, b"")))}",',
            f"  number: {one(v, 3, 0)},",
            f"  label: {one(v, 4, 1)},",
            f"  type_code: {one(v, 5, 0)},",
            f"  type_name: {opt_str(text(one(v, 6)) if one(v, 6) is not None else None)},",
            f'  json_name: {opt_str(text(one(v, 10)) if one(v, 10) is not None else None)},',
            f'  default_value: {opt_str(text(one(v, 7)) if one(v, 7) is not None else None)},',
            f"  oneof_index: {opt_int(one(v, 9))},",
            f"  proto3_optional: {bool_text(one(v, 17, 0) == 1)},",
            f"  packed_off: {bool_text(packed_off)},",
            f'  extendee: {opt_str(text(one(v, 2)) if one(v, 2) is not None else None)},',
            f"  features: {features_text(own)},",
            "  options: [],",
            "}",
        ]
    )


def parse_range(data: bytes) -> str:
    v = group(data)
    return f"({one(v, 1, 0)}, {one(v, 2, 0)})"


def parse_enum_value(data: bytes) -> str:
    v = group(data)
    return (
        "{\n"
        f'  name: "{esc(text(one(v, 1, b"")))}",\n'
        f"  number: {one(v, 2, 0)},\n"
        "}"
    )


def parse_enum(data: bytes, parent: dict[str, int]) -> str:
    v = group(data)
    own = merge(parent, read_features(one(v, 3), "enum"))
    values = [parse_enum_value(item) for item in v.get(2, [])]
    return "\n".join(
        [
            "{",
            f'  name: "{esc(text(one(v, 1, b"")))}",',
            "  value: " + array_text(values, "  ") + ",",
            f"  features: {features_text(own)},",
            "  options: [],",
            "}",
        ]
    )


def parse_message(data: bytes, parent: dict[str, int], em: Emitter) -> str:
    v = group(data)
    own = merge(parent, read_features(one(v, 7), "message"))
    map_entry = False
    if one(v, 7) is not None:
        for number, _wire, value in wire_fields(one(v, 7)):
            if number == 7 and value == 1:
                map_entry = True
    nested = [parse_message(item, own, em) for item in v.get(3, [])]
    fields = [parse_field(item, own) for item in v.get(2, [])]
    enums = [parse_enum(item, own) for item in v.get(4, [])]
    extensions = [parse_field(item, own) for item in v.get(6, [])]
    oneofs = []
    for item in v.get(8, []):
        oneofs.append('{\n  name: "' + esc(text(one(group(item), 1, b""))) + '",\n}')
    reserved_ranges = [parse_range(item) for item in v.get(9, [])]
    extension_ranges = [parse_range(item) for item in v.get(5, [])]
    reserved_names = [f'"{esc(text(item))}"' for item in v.get(10, [])]
    body = "\n".join(
        [
            "{",
            f'  name: "{esc(text(one(v, 1, b"")))}",',
            "  field: " + array_text(fields, "  ") + ",",
            "  nested_type: " + array_text(nested, "  ") + ",",
            "  enum_type: " + array_text(enums, "  ") + ",",
            "  extension: " + array_text(extensions, "  ") + ",",
            "  oneof_decl: " + array_text(oneofs, "  ") + ",",
            "  reserved_range: " + array_text(reserved_ranges, "  ") + ",",
            "  reserved_name: " + array_text(reserved_names, "  ") + ",",
            "  extension_range: " + array_text(extension_ranges, "  ") + ",",
            f"  map_entry: {bool_text(map_entry)},",
            f"  features: {features_text(own)},",
            "  options: [],",
            "}",
        ]
    )
    return em.add("DescriptorProto", body)


def parse_file(data: bytes, em: Emitter) -> str:
    v = group(data)
    parent = read_features(one(v, 8), "file")
    syntax = text(one(v, 12, b"proto2"))
    edition = EDITIONS.get(one(v, 14))
    messages = [parse_message(item, parent, em) for item in v.get(4, [])]
    enums = [parse_enum(item, parent) for item in v.get(5, [])]
    extensions = [parse_field(item, parent) for item in v.get(7, [])]
    dependencies = [f'"{esc(text(item))}"' for item in v.get(3, [])]
    body = "\n".join(
        [
            "{",
            f'  name: "{esc(text(one(v, 1, b"")))}",',
            f'  package_name: "{esc(text(one(v, 2, b"")))}",',
            f'  syntax: "{esc(syntax)}",',
            "  message_type: " + array_text(messages, "  ") + ",",
            "  enum_type: " + array_text(enums, "  ") + ",",
            "  service: [],",
            "  extension: " + array_text(extensions, "  ") + ",",
            "  dependency: " + array_text(dependencies, "  ") + ",",
            "  public_dependency: [],",
            f"  edition: {opt_str(edition)},",
            f"  features: {features_text(parent)},",
            "  options: [],",
            "}",
        ]
    )
    return em.add("FileDescriptorProto", body)


def main() -> None:
    blob = (Path(sys.argv[1]) if len(sys.argv) > 1 else SOURCE).read_bytes()
    em = Emitter()
    files = [parse_file(item, em) for number, _wire, item in wire_fields(blob) if number == 1]
    lines = [
        "// Generated by scripts/gen_conformance_types.py from",
        "// tests/conformance/descriptor_set.bin (protobuf 36.2). Do not edit.",
        "//",
        "// The official conformance runner names its messages by full proto name;",
        "// these records let the testee build those descriptors with @desc and",
        "// register them as dynamic messages.",
        "",
    ]
    lines.extend(em.definitions)
    lines.append("///|")
    lines.append("pub fn official_files() -> Array[@desc.FileDescriptorProto] {")
    lines.append("  [")
    for call in files:
        lines.append(f"    {call},")
    lines += ["  ]", "}", ""]
    (Path(sys.argv[2]) if len(sys.argv) > 2 else TARGET).write_text(
        "\n".join(lines), encoding="utf-8", newline="\n"
    )
    print(f"wrote {len(files)} conformance file descriptors in {em.counter} segments")


if __name__ == "__main__":
    main()
