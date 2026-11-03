// The builder's job: turn the proto form into descriptors with the right kinds,
// cardinality, map pairs and required set.

///|
fn field(
  name : String,
  number : Int32,
  label : Int32,
  type_code : Int32,
  type_name : String?,
) -> FieldDescriptorProto {
  {
    name,
    number,
    label,
    type_code,
    type_name,
    json_name: None,
    default_value: None,
    oneof_index: None,
    proto3_optional: false,
    packed_off: false,
    extendee: None,
    features: features_auto,
    options: [],
  }
}

///|
test "proto3 fields, a map, an enum and a nested message" {
  let entry : DescriptorProto = {
    name: "CountsEntry",
    field: [field("key", 1, 1, 9, None), field("value", 2, 1, 5, None)],
    nested_type: [],
    enum_type: [],
    extension: [],
    oneof_decl: [],
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry: true,
    features: features_auto,
    options: [],
  }
  let inner : DescriptorProto = {
    name: "Inner",
    field: [field("x", 1, 1, 5, None)],
    nested_type: [],
    enum_type: [],
    extension: [],
    oneof_decl: [],
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry: false,
    features: features_auto,
    options: [],
  }
  let message : DescriptorProto = {
    name: "M",
    field: [
      field("i", 1, 1, 5, None),
      field("tags", 2, 3, 9, None),
      field("counts", 3, 3, 11, Some(".test.M.CountsEntry")),
      field("inner", 4, 1, 11, Some(".test.M.Inner")),
      field("color", 5, 1, 14, Some(".test.M.Color")),
      field("nums", 6, 3, 5, None),
    ],
    nested_type: [entry, inner],
    enum_type: [
      {
        name: "Color",
        value: [{ name: "RED", number: 0, }, { name: "BLUE", number: 1, }],
        features: features_auto,
        options: [],
      },
    ],
    extension: [],
    oneof_decl: [],
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry: false,
    features: features_auto,
    options: [],
  }
  let file : FileDescriptorProto = {
    name: "test.proto",
    package_name: "test",
    syntax: "proto3",
    message_type: [message],
    enum_type: [],
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
    edition: None,
    features: features_auto,
    options: [],
  }
  let built = build_file(file)
  assert_eq(built.path, "test.proto")
  assert_eq(built.messages.length(), 1)
  let m = built.messages[0]
  assert_eq(m.full_name, "test.M")
  let counts = match m.field_by_number(3) {
    Some(field) => field
    None => abort("missing counts")
  }
  assert_true(counts.is_map)
  match counts.map_key_field {
    Some(key) => assert_eq(key.kind == @reflect.String, true)
    None => abort("missing map key")
  }
  assert_eq(counts.packed, false)
  let tags = match m.field_by_number(2) {
    Some(field) => field
    None => abort("missing tags")
  }
  assert_true(tags.is_list())
  assert_true(!tags.packed)
  let nums = match m.field_by_number(6) {
    Some(field) => field
    None => abort("missing nums")
  }
  assert_true(nums.packed)
  let color = match m.field_by_number(5) {
    Some(field) => field
    None => abort("missing color")
  }
  assert_true(color.enum_type == Some("test.M.Color"))
  assert_eq(m.nested_enums.length(), 1)
  assert_eq(m.nested_messages.length(), 2)
}

///|
test "proto2 required fields land in the required set" {
  let message : DescriptorProto = {
    name: "P",
    field: [field("must", 1, 2, 5, None), field("maybe", 2, 1, 5, None)],
    nested_type: [],
    enum_type: [],
    extension: [],
    oneof_decl: [],
    reserved_range: [],
    reserved_name: [],
    extension_range: [],
    map_entry: false,
    features: features_auto,
    options: [],
  }
  let file : FileDescriptorProto = {
    name: "p.proto",
    package_name: "p",
    syntax: "proto2",
    message_type: [message],
    enum_type: [],
    service: [],
    extension: [],
    dependency: [],
    public_dependency: [],
    edition: None,
    features: features_auto,
    options: [],
  }
  let built = build_file(file)
  assert_eq(built.syntax == @reflect.Proto2, true)
  assert_eq(built.messages[0].required_numbers.length(), 1)
  assert_eq(built.messages[0].required_numbers[0], 1)
}

///|
test "json_name defaults to camel case" {
  assert_eq(to_json_name("foo_bar"), "fooBar")
  assert_eq(to_json_name("foo"), "foo")
  assert_eq(to_json_name("a_b_c"), "aBC")
}
