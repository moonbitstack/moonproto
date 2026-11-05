// Command gointerop exchanges the shared interop.proto fixture with the
// MoonBit implementation. It speaks two verbs on standard input/output:
//
//	encode  read a text-format message on stdin, write lowercase hex of the
//	        binary encoding;
//	decode  read lowercase hex on stdin, decode it, assert every field value,
//	        and write the hex of a deterministic re-encoding.
//
// The generated binding comes from protoc-gen-go v1.36.12 over
// tests/interop/interop.proto, exactly the file the MoonBit side parses.
package main

import (
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strings"

	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"
)

func readAll() string {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		fail(err)
	}
	return string(data)
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

// assertValues checks that a decoded message carries every value of the
// fixture, not merely that it can be parsed and re-encoded.
func assertValues(m *All) {
	want := []struct {
		name string
		got  any
		exp  any
	}{
		{"i32", m.GetI32(), int32(150)},
		{"i64", m.GetI64(), int64(10000000000)},
		{"u32", m.GetU32(), uint32(7)},
		{"u64", m.GetU64(), uint64(8)},
		{"s32", m.GetS32(), int32(-1)},
		{"s64", m.GetS64(), int64(-2)},
		{"f32", m.GetF32(), uint32(1065353216)},
		{"f64", m.GetF64(), uint64(4607182418800017408)},
		{"sf32", m.GetSf32(), int32(-3)},
		{"sf64", m.GetSf64(), int64(-4)},
		{"flt", m.GetFlt(), float32(2.5)},
		{"dbl", m.GetDbl(), float64(3.5)},
		{"flag", m.GetFlag(), true},
		{"text", m.GetText(), "hi"},
		{"blob", hex.EncodeToString(m.GetBlob()), "0102"},
		{"nums", fmt.Sprint(m.GetNums()), "[1 300]"},
		{"names", fmt.Sprint(m.GetNames()), "[a b]"},
		{"counts", fmt.Sprint(m.GetCounts()), "map[k:5]"},
		{"inner", m.GetInner().GetX(), int32(9)},
		{"color", m.GetColor(), Color_BLUE},
		{"pick_s", m.GetPickS(), "x"},
	}
	for _, item := range want {
		if item.got != item.exp {
			fail(fmt.Errorf("%s: got %v, want %v", item.name, item.got, item.exp))
		}
	}
}

func marshal(m *All) string {
	data, err := (proto.MarshalOptions{Deterministic: true}).Marshal(m)
	if err != nil {
		fail(err)
	}
	return hex.EncodeToString(data)
}

func main() {
	if len(os.Args) != 2 {
		fail(fmt.Errorf("usage: gointerop encode|decode"))
	}
	in := strings.TrimSpace(readAll())
	switch os.Args[1] {
	case "encode":
		m := &All{}
		if err := (prototext.UnmarshalOptions{DiscardUnknown: false}).Unmarshal([]byte(in), m); err != nil {
			fail(err)
		}
		assertValues(m)
		fmt.Println(marshal(m))
	case "decode":
		data, err := hex.DecodeString(in)
		if err != nil {
			fail(err)
		}
		m := &All{}
		if err := proto.Unmarshal(data, m); err != nil {
			fail(err)
		}
		assertValues(m)
		fmt.Println(marshal(m))
	default:
		fail(fmt.Errorf("unknown verb %q", os.Args[1]))
	}
}
