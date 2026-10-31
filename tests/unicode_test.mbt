///|
fn unicode_capture_code(code : Int32) -> Array[Int32] {
  [
    0xf3,
    0x4f,
    3,
    2,
    88,
    190,
    11,
    0x3f,
    code >> 8,
    code & 255,
    0xf3,
    0x3f,
    255,
    253,
    0xd0,
    0x1f,
    2,
    90,
    0,
    16,
    0xe6,
    0xbf,
    16,
    186,
  ]
}

///|
fn captured_unicode(code : Int32) -> String raise {
  output(5, unicode_capture_code(code))
}

///|
test "print_unicode ASCII obeys the memory output stream" {
  assert_eq(captured_unicode(65), "65")
}

///|
test "print_unicode maps accented Unicode back to default ZSCII" {
  assert_eq(captured_unicode(228), "155")
}

///|
test "print_unicode uses question mark when stream 3 cannot represent a character" {
  assert_eq(captured_unicode(0x6c49), "63")
}

///|
test "print_unicode obeys disabled screen output" {
  assert_eq(output(5, [0xf3, 0x3f, 255, 255, 190, 11, 0x3f, 0, 65, 186]), "")
}

///|
fn translated_story(
  code : Array[Int32],
  count : Int32,
  character : Int32,
) -> Bytes {
  let story = fixture(5, code)
  let bytes = Array::makei(story.length(), i => story[i])
  for (addr, value) in [(54, 650), (650, 3), (656, 670), (671, character)] {
    bytes[addr] = (value >> 8).to_byte()
    bytes[addr + 1] = value.to_byte()
  }
  bytes[670] = count.to_byte()
  Bytes::from_array(bytes)
}

///|
test "custom translation table maps Unicode to memory ZSCII" {
  let m = @zvm.Machine::new(
    translated_story(unicode_capture_code(0x03a9), 1, 0x03a9),
  )
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "155")
}

///|
test "custom translation table maps ZSCII to screen Unicode" {
  let m = @zvm.Machine::new(translated_story([0xe5, 0x7f, 155, 186], 1, 0x03a9))
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "Ω")
}

///|
test "custom translation table does not fall back to default outside its range" {
  let m = @zvm.Machine::new(translated_story([0xe5, 0x7f, 156, 186], 1, 0x03a9))
  let rejected = try {
    let _ = m.run()
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "oversized translation table is rejected" {
  let m = @zvm.Machine::new(translated_story([0xe5, 0x7f, 155, 186], 98, 65))
  let rejected = try {
    let _ = m.run()
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "surrogate translation entries are rejected" {
  let m = @zvm.Machine::new(translated_story([0xe5, 0x7f, 155, 186], 1, 0xd800))
  let rejected = try {
    let _ = m.run()
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}
