///|
fn header_fixture(version : Int32, changes : Array[(Int32, Int32)]) -> Bytes {
  let story = fixture(version, [186])
  let bytes = Array::makei(story.length(), i => story[i])
  for (offset, value) in changes {
    bytes[offset] = value.to_byte()
  }
  Bytes::from_array(bytes)
}

///|
test "story inspector reports raw header fields" {
  let info = @zvm.inspect_story(
    header_fixture(5, [
      (2, 0x12),
      (3, 0x34),
      (18, 50),
      (19, 54),
      (20, 49),
      (21, 48),
      (22, 51),
      (23, 49),
    ]),
  )
  assert_eq(info.version, 5)
  assert_eq(info.release, 0x1234)
  assert_eq(info.serial, "261031")
  assert_eq(info.initial_pc, 768)
  assert_eq(info.static_memory, 768)
  assert_eq(info.high_memory, 768)
  assert_eq(info.actual_length, 2048)
  assert_eq(info.checksum_valid, None)
}

///|
test "story inspector verifies checksum up to declared length" {
  // Code is one @quit byte; padding after byte 771 is deliberately ignored.
  let info = @zvm.inspect_story(
    header_fixture(5, [(26, 0), (27, 193), (28, 0), (29, 186), (1800, 7)]),
  )
  assert_eq(info.declared_length, 772)
  assert_eq(info.checksum_valid, Some(true))
}

///|
test "story inspector reports checksum mismatch without executing" {
  assert_eq(
    @zvm.inspect_story(header_fixture(3, [(26, 4), (27, 0), (29, 1)])).checksum_valid,
    Some(false),
  )
}

///|
test "serial metadata cannot inject terminal control characters" {
  assert_eq(
    @zvm.inspect_story(header_fixture(5, [(18, 27), (19, 0), (20, 255)])).serial,
    "??????",
  )
}

///|
test "truncated declared story is rejected" {
  let rejected = try {
    let _ = @zvm.inspect_story(header_fixture(5, [(26, 2), (27, 1)]))
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "high memory cannot overlap writable dynamic memory" {
  let rejected = try {
    let _ = @zvm.inspect_story(header_fixture(5, [(4, 0), (5, 64)]))
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}
