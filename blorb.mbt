///|
fn iff_tag(data : Bytes, at : Int32, tag : Bytes) -> Bool {
  at >= 0 &&
  at <= data.length() - 4 &&
  data[at] == tag[0] &&
  data[at + 1] == tag[1] &&
  data[at + 2] == tag[2] &&
  data[at + 3] == tag[3]
}

///|
// Lengths/offsets must fit the bounded input before any addition or allocation.
fn iff_size(data : Bytes, at : Int32) -> Int32 raise Fault {
  if at < 0 || at > data.length() - 4 || data[at].to_int() >= 128 {
    raise Invalid("invalid Blorb length or offset")
  }
  let n = (data[at].to_int() << 24) |
    (data[at + 1].to_int() << 16) |
    (data[at + 2].to_int() << 8) |
    data[at + 3].to_int()
  if n > data.length() {
    raise Invalid("Blorb length or offset exceeds input")
  }
  n
}

///|
/// Return validated raw v3/v5 bytes, or extract Exec 0 from a Blorb IFRS FORM.
/// Containers are limited to 16 MiB; pictures and sound resources are ignored.
pub fn extract_story(data : Bytes) -> Bytes raise Fault {
  if !iff_tag(data, 0, b"FORM") {
    let _ = inspect_story(data)
    return data
  }
  if data.length() > 16777216 ||
    data.length() < 24 ||
    !iff_tag(data, 8, b"IFRS") ||
    iff_size(data, 4) != data.length() - 8 {
    raise Invalid("invalid Blorb FORM (maximum 16 MiB, no trailing bytes)")
  }
  if !iff_tag(data, 12, b"RIdx") {
    raise Invalid("Blorb must begin with RIdx")
  }
  let index_size = iff_size(data, 16)
  if index_size < 4 || index_size > data.length() - 20 {
    raise Invalid("truncated Blorb index")
  }
  let count = iff_size(data, 20)
  if count > (index_size - 4) / 12 || count * 12 != index_size - 4 {
    raise Invalid("invalid Blorb index count")
  }
  let mut executable = -1
  for i in 0..<count {
    let at = 24 + i * 12
    if iff_tag(data, at, b"Exec") && iff_size(data, at + 4) == 0 {
      if executable != -1 {
        raise Invalid("duplicate Blorb Exec 0")
      }
      executable = iff_size(data, at + 8)
    }
  }
  if executable == -1 {
    raise Invalid("Blorb has no Exec 0 resource")
  }
  let mut pos = 12
  let mut start = -1
  let mut length = 0
  while pos < data.length() {
    if pos > data.length() - 8 {
      raise Invalid("truncated Blorb chunk header")
    }
    let n = iff_size(data, pos + 4)
    if n > data.length() - pos - 8 {
      raise Invalid("truncated Blorb chunk")
    }
    if pos != 12 && iff_tag(data, pos, b"RIdx") {
      raise Invalid("duplicate Blorb index")
    }
    if pos == executable {
      if !iff_tag(data, pos, b"ZCOD") {
        raise Invalid("Blorb Exec 0 is not Z-code")
      }
      start = pos + 8
      length = n
    }
    let end = pos + 8 + n
    if (n & 1) != 0 && end == data.length() {
      raise Invalid("missing Blorb padding byte")
    }
    pos = end + (n & 1)
  }
  if start == -1 {
    raise Invalid("Blorb Exec offset is not a chunk boundary")
  }
  // Check the embedded version size before copying potentially large resources.
  if length < 64 || length > 262144 {
    raise Invalid("Blorb Z-code size is unsupported")
  }
  let story = Bytes::from_array(Array::makei(length, i => data[start + i]))
  let _ = inspect_story(story)
  story
}
