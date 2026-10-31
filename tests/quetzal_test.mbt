///|
fn qlong(bytes : Array[Int32], n : Int32) -> Unit {
  for shift in [24, 16, 8, 0] {
    bytes.push((n >> shift) & 255)
  }
}

///|
fn qchunk(bytes : Array[Int32], name : String, payload : Array[Int32]) -> Unit {
  for c in name.to_array() {
    bytes.push(c.to_int())
  }
  qlong(bytes, payload.length())
  for b in payload {
    bytes.push(b)
  }
  if payload.length() % 2 == 1 {
    bytes.push(0)
  }
}

///|
fn compressed_save(payload : Array[Int32]) -> Bytes {
  let body = [73, 70, 90, 83] // IFZS
  // Identity fields match the zero-filled fixture; PC=771, the store byte.
  qchunk(body, "IFhd", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3])
  qchunk(body, "CMem", payload)
  qchunk(body, "Stks", [0, 0, 0, 0, 0, 0, 0, 0])
  let bytes = [70, 79, 82, 77] // FORM
  qlong(bytes, body.length())
  for b in body {
    bytes.push(b)
  }
  Bytes::from_array(bytes.map(i => i.to_byte()))
}

///|
test "independent Quetzal CMem vector decodes XOR and zero run" {
  let m = @zvm.Machine::new(fixture(5, [190, 1, 255, 16, 0xe6, 0xbf, 17, 186]))
  assert_eq(m.run(), "restore")
  // Skip 66 unchanged bytes, then flip byte 66; omitted tail is unchanged.
  m.restore_data(compressed_save([0, 65, 1]))
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "256")
}

///|
test "empty CMem restores original dynamic memory" {
  let m = @zvm.Machine::new(fixture(5, [190, 1, 255, 16, 0xe6, 0xbf, 17, 186]))
  assert_eq(m.run(), "restore")
  m.restore_data(compressed_save([]))
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "0")
}

///|
test "CMem overrun rejects atomically" {
  let m = @zvm.Machine::new(fixture(5, [190, 1, 255, 16, 186]))
  assert_eq(m.run(), "restore")
  let at = m.position()
  let rejected = try {
    m.restore_data(compressed_save([0, 255, 0, 255, 0, 255, 0, 0]))
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
  assert_eq(m.position(), at)
  assert_eq(m.run(), "restore")
}

///|
test "truncated CMem run rejects atomically" {
  let m = @zvm.Machine::new(fixture(5, [190, 1, 255, 16, 186]))
  assert_eq(m.run(), "restore")
  let rejected = try {
    m.restore_data(compressed_save([0]))
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
  assert_eq(m.run(), "restore")
}

///|
test "invalid v3 restored branch rejects before changing the machine" {
  let m = @zvm.Machine::new(fixture(3, [182, 194, 186, 0xa0, 0, 186]))
  assert_eq(m.run(), "restore")
  let at = m.position()
  // IFhd resumes at byte 771, whose signed branch points before the story.
  let rejected = try {
    m.restore_data(compressed_save([]))
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
  assert_eq(m.position(), at)
  assert_eq(m.run(), "restore")
}
