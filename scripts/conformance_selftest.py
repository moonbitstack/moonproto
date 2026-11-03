#!/usr/bin/env python3
"""Drive cmd/conformance-mbt over the runner's framing and check the answers.

The official runner is a C++ binary that this repository does not ship; when it
is on PATH, scripts/conformance.sh runs it against this same testee. This script
is the check that always runs: it frames a few requests the way the runner does
and asserts the response fields.
"""
import struct
import subprocess
import sys


def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            return out + bytes([b])


def ld(field, payload):
    return varint((field << 3) | 2) + varint(len(payload)) + payload


def vi(field, value):
    return varint((field << 3) | 0) + varint(value)


def request(payload_field, payload, output_format, message_type="conformance.TestAllTypes"):
    return ld(payload_field, payload) + vi(3, output_format) + ld(4, message_type.encode())


def frame(body):
    return struct.pack("<I", len(body)) + body


def parse(body):
    out, at = {}, 0
    while at < len(body):
        tag, at = read_varint(body, at)
        field, wire = tag >> 3, tag & 7
        if wire == 2:
            size, at = read_varint(body, at)
            out[field] = body[at : at + size]
            at += size
        elif wire == 0:
            value, at = read_varint(body, at)
            out[field] = value
        else:
            raise SystemExit(f"unexpected wire type {wire}")
    return out


def read_varint(body, at):
    value, shift = 0, 0
    while True:
        byte = body[at]
        at += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, at
        shift += 7


def main():
    exe = sys.argv[1]
    # Field 1 is i32; 08 96 01 is 150.
    cases = [
        ("binary to JSON", request(1, bytes.fromhex("089601"), 2), 4, b'"i32":150'),
        ("JSON to binary", request(2, b'{"i32":150}', 1), 3, bytes.fromhex("089601")),
        ("binary to text", request(1, bytes.fromhex("089601"), 4), 7, b"i32: 150"),
    ]
    payload = b"".join(frame(case[1]) for case in cases)
    result = subprocess.run([exe], input=payload, capture_output=True)
    out, at, index = result.stdout, 0, 0
    while at + 4 <= len(out):
        size = struct.unpack("<I", out[at : at + 4])[0]
        body = out[at + 4 : at + 4 + size]
        at += 4 + size
        name, _, field, expected = cases[index]
        answer = parse(body)
        if "error" in [k for k in (1, 2) if k in answer]:
            raise SystemExit(f"{name}: testee reported an error: {body!r}")
        got = answer.get(field)
        if got is None:
            raise SystemExit(f"{name}: response has no field {field}: {body!r}")
        if expected not in got:
            raise SystemExit(f"{name}: expected {expected!r} in {got!r}")
        index += 1
        print(f"ok {name}")
    if index != len(cases):
        raise SystemExit(f"only {index} of {len(cases)} responses came back")
    print("framing self-check passed")


if __name__ == "__main__":
    main()
