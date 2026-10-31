///|
/// Original story metadata, before interpreter capability flags are installed.
pub struct StoryInfo {
  version : Int32
  release : Int32
  serial : String
  initial_pc : Int32
  high_memory : Int32
  static_memory : Int32
  dictionary : Int32
  objects : Int32
  globals : Int32
  abbreviations : Int32
  actual_length : Int32
  declared_length : Int32
  checksum : Int32
  checksum_valid : Bool?
}

///|
fn header_word(story : Bytes, offset : Int32) -> Int32 {
  story[offset].to_int() * 256 + story[offset + 1].to_int()
}

///|
/// Inspect a raw v3/v5 story without executing code or requesting host entropy.
/// The six-byte serial is made printable for safe terminal presentation.
pub fn inspect_story(story : Bytes) -> StoryInfo raise Fault {
  if story.length() < 64 {
    raise Invalid("truncated header")
  }
  let version = story[0].to_int()
  if version != 3 && version != 5 {
    raise Invalid("only story versions 3 and 5 are supported")
  }
  let max_size = if version == 3 { 131072 } else { 262144 }
  if story.length() > max_size {
    raise Invalid("story exceeds version size limit")
  }
  let static_memory = header_word(story, 14)
  let high_memory = header_word(story, 4)
  let globals = header_word(story, 12)
  let objects = header_word(story, 10)
  let initial_pc = header_word(story, 6)
  if static_memory < 64 ||
    static_memory > story.length() ||
    globals < 64 ||
    globals > static_memory - 480 ||
    objects < 64 ||
    objects >= static_memory ||
    high_memory < static_memory ||
    high_memory >= story.length() ||
    initial_pc < 64 ||
    initial_pc >= story.length() {
    raise Invalid("invalid memory map")
  }
  let declared_length = header_word(story, 26) *
    (if version == 3 { 2 } else { 4 })
  if declared_length != 0 &&
    (declared_length < 64 || declared_length > story.length()) {
    raise Invalid(
      "declared story length exceeds available bytes or omits the header",
    )
  }
  let checksum = header_word(story, 28)
  let checksum_valid = if declared_length == 0 {
    None
  } else {
    let mut sum = 0
    for i in 64..<declared_length {
      sum = (sum + story[i].to_int()) & 65535
    }
    Some(sum == checksum)
  }
  let serial = StringBuilder()
  for i in 18..<24 {
    let c = story[i].to_int()
    serial.write_char(
      (if c >= 32 && c <= 126 { c } else { 63 }).unsafe_to_char(),
    )
  }
  {
    version,
    release: header_word(story, 2),
    serial: serial.to_string(),
    initial_pc,
    high_memory,
    static_memory,
    dictionary: header_word(story, 8),
    objects,
    globals,
    abbreviations: header_word(story, 24),
    actual_length: story.length(),
    declared_length,
    checksum,
    checksum_valid,
  }
}
