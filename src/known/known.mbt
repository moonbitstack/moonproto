// The well-known types, as the generated package defines them.

///|
/// Every well-known file, in the order protobuf lists them.
pub fn files() -> Array[@reflect.FileDescriptor] raise @desc.Refused {
  [
    @gp.file_descriptor_google_protobuf_any_proto(),
    @gp.file_descriptor_google_protobuf_duration_proto(),
    @gp.file_descriptor_google_protobuf_empty_proto(),
    @gp.file_descriptor_google_protobuf_field_mask_proto(),
    @gp.file_descriptor_google_protobuf_struct_proto(),
    @gp.file_descriptor_google_protobuf_timestamp_proto(),
    @gp.file_descriptor_google_protobuf_wrappers_proto(),
  ]
}

///|
/// `descriptor.proto`, which carries the descriptor messages themselves.
pub fn descriptor_file() -> @reflect.FileDescriptor raise @desc.Refused {
  @gp.file_descriptor_google_protobuf_descriptor_proto()
}

///|
/// The first file that declares `name`, or the descriptor file.
pub fn file_descriptor() -> @reflect.FileDescriptor raise @desc.Refused {
  descriptor_file()
}

///|
/// Look a message up by its qualified name.
pub fn message_descriptor(
  name : String,
) -> @reflect.MessageDescriptor? raise @desc.Refused {
  for file in files() {
    match find_in(file.messages, name) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  match find_in(descriptor_file().messages, name) {
    Some(found) => Some(found)
    None => None
  }
}

///|
fn find_in(
  messages : Array[@reflect.MessageDescriptor],
  name : String,
) -> @reflect.MessageDescriptor? {
  for message in messages {
    if message.full_name == name {
      return Some(message)
    }
    match find_in(message.nested_messages, name) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
/// Register every well-known type, so the codecs can resolve a message by name.
/// Registering twice is harmless.
pub fn register_all() -> Unit {
  let all = files() catch { _ => [] }
  let descriptors = all +
    [descriptor_file() catch { _ => abort("no descriptor.proto") }]
  for file in descriptors {
    register_file(file)
  }
}

///|
fn register_file(file : @reflect.FileDescriptor) -> Unit {
  for message in file.messages {
    @reflect.global_types.register_message(@dynamic.new_message_type(message)) catch {
      _ => ()
    }
    register_messages(message.nested_messages)
  }
  for item in file.enums {
    @reflect.global_types.register_enum(@dynamic.new_enum_type(item)) catch {
      _ => ()
    }
  }
  for extension in file.extensions {
    @reflect.global_types.register_extension(
      @dynamic.new_extension_type(extension),
    ) catch {
      _ => ()
    }
  }
  @reflect.global_files.register(file) catch {
    _ => ()
  }
}

///|
fn register_messages(messages : Array[@reflect.MessageDescriptor]) -> Unit {
  for message in messages {
    @reflect.global_types.register_message(@dynamic.new_message_type(message)) catch {
      _ => ()
    }
    register_messages(message.nested_messages)
  }
}
