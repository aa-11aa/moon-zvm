///|
fn blorb_long(bytes : Array[Byte], at : Int32, n : Int32) -> Unit {
  for i in 0..<4 {
    bytes[at + i] = ((n >> (24 - i * 8)) & 255).to_byte()
  }
}

///|
fn blorb_fixture(story : Bytes, odd_chunk~ : Bool = false) -> Bytes {
  let offset = if odd_chunk { 46 } else { 36 }
  let bytes = Array::make(
    offset + 8 + story.length() + (story.length() & 1),
    (0).to_byte(),
  )
  for
    (at, tag) in [
      (0, b"FORM"),
      (8, b"IFRS"),
      (12, b"RIdx"),
      (24, b"Exec"),
      (offset, b"ZCOD"),
    ] {
    for i in 0..<4 {
      bytes[at + i] = tag[i]
    }
  }
  blorb_long(bytes, 4, bytes.length() - 8)
  blorb_long(bytes, 16, 16)
  blorb_long(bytes, 20, 1)
  blorb_long(bytes, 32, offset)
  blorb_long(bytes, offset + 4, story.length())
  if odd_chunk {
    for i in 0..<4 {
      bytes[36 + i] = b"ANNO"[i]
    }
    blorb_long(bytes, 40, 1)
    bytes[44] = (65).to_byte()
  }
  for i in 0..<story.length() {
    bytes[offset + 8 + i] = story[i]
  }
  Bytes::from_array(bytes)
}

///|
test "extract raw or indexed v3 and v5 executable" {
  for version in [3, 5] {
    let story = fixture(version, [186])
    for
      bytes in [
        story,
        blorb_fixture(story),
        blorb_fixture(story, odd_chunk=true),
      ] {
      let raw = @zvm.extract_story(bytes)
      assert_eq(raw, story)
      let vm = @zvm.Machine::new(raw)
      assert_eq(vm.run(), "halted")
    }
  }
}

///|
fn rejected_blorb(bytes : Bytes) -> Bool {
  try {
    let _ = @zvm.extract_story(bytes)
    false
  } catch {
    @zvm.Invalid(_) => true
  }
}

///|
test "Blorb offsets cannot point into a chunk payload" {
  let container = blorb_fixture(fixture(5, [186]))
  let bytes = Array::makei(container.length(), i => container[i])
  for offset in [0, 12, 24, 35, 37, 44, 100, container.length()] {
    blorb_long(bytes, 32, offset)
    assert_true(rejected_blorb(Bytes::from_array(bytes)))
  }
}

///|
test "Blorb rejects wrong form, index and executable types" {
  let container = blorb_fixture(fixture(5, [186]))
  for at in [0, 8, 12, 24, 36] {
    let bytes = Array::makei(container.length(), i => container[i])
    bytes[at] = (0).to_byte()
    assert_true(rejected_blorb(Bytes::from_array(bytes)))
  }
}

///|
test "Blorb rejects overflowing lengths and inconsistent resource counts" {
  let container = blorb_fixture(fixture(5, [186]))
  for at in [4, 16, 20, 32, 40] {
    for value in [1, 0x7fffffff, -1] {
      let bytes = Array::makei(container.length(), i => container[i])
      blorb_long(bytes, at, if at == 20 && value == 1 { 2 } else { value })
      assert_true(rejected_blorb(Bytes::from_array(bytes)))
    }
  }
}

///|
test "Blorb rejects unsupported embedded versions" {
  assert_true(rejected_blorb(blorb_fixture(fixture(6, [186]))))
}

///|
test "Blorb rejects duplicate Exec zero entries" {
  let container = blorb_fixture(fixture(5, [186]))
  let bytes = Array::make(container.length() + 12, (0).to_byte())
  for i in 0..<36 {
    bytes[i] = container[i]
  }
  for i in 0..<12 {
    bytes[36 + i] = container[24 + i]
  }
  for i in 36..<container.length() {
    bytes[i + 12] = container[i]
  }
  blorb_long(bytes, 4, bytes.length() - 8)
  blorb_long(bytes, 16, 28)
  blorb_long(bytes, 20, 2)
  blorb_long(bytes, 32, 48)
  blorb_long(bytes, 44, 48)
  assert_true(rejected_blorb(Bytes::from_array(bytes)))
}
