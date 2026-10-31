///|
test "all first opcodes can be inspected without mutating live state" {
  for version in [3, 5] {
    for opcode in 0..<256 {
      let machine = @zvm.Machine::new(
        fixture(version, [opcode, 255, 255, 255, 255, 255, 255, 255]),
      )
      let before = machine.position()
      try {
        let instruction = machine.peek_instruction()
        assert_eq(instruction.address, before)
        assert_true(instruction.next_address > before)
        assert_true(instruction.next_address <= 2048)
      } catch {
        @zvm.Invalid(_) => ()
        error => raise error
      }
      assert_eq(machine.position(), before)
      assert_eq(machine.take_output(), "")
    }
  }
}

///|
test "instruction inspection rejects truncated operands, branch and inline text" {
  for
    code in [
      [0x80],
      [0x80, 1],
      [0x90, 0],
      [0x90, 0, 0x80],
      [178, 0],
      [190],
      [190, 2],
    ] {
    let story = fixture(5, [186])
    let bytes = Array::makei(story.length(), i => story[i])
    let start = bytes.length() - code.length()
    for i in 0..<code.length() {
      bytes[start + i] = code[i].to_byte()
    }
    let rejected = try {
      let _ = @zvm.inspect_instruction(Bytes::from_array(bytes), start)
      false
    } catch {
      @zvm.Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "all truncated Blorb prefixes return a format fault" {
  let container = blorb_fixture(header_fixture(5, [(26, 2), (27, 0)]))
  for size in 0..<container.length() {
    let bytes = Array::makei(size, i => container[i])
    // Keep the FORM envelope consistent to exercise inner chunk bounds too.
    if size >= 8 {
      blorb_long(bytes, 4, size - 8)
    }
    assert_true(rejected_blorb(Bytes::from_array(bytes)))
  }
}

///|
test "deterministic malformed container mutations never escape Fault handling" {
  let container = blorb_fixture(fixture(5, [186]), odd_chunk=true)
  let mut seed = 7
  for _ in 0..<1024 {
    let bytes = Array::makei(container.length(), i => container[i])
    for _ in 0..<4 {
      seed = (seed * 25173 + 13849) & 65535
      let at = seed % 64
      seed = (seed * 25173 + 13849) & 65535
      bytes[at] = (seed & 255).to_byte()
    }
    try {
      let raw = @zvm.extract_story(Bytes::from_array(bytes))
      let info = @zvm.inspect_story(raw)
      assert_true(info.version == 3 || info.version == 5)
      assert_true(raw.length() <= 262144)
    } catch {
      @zvm.Invalid(_) => ()
      error => raise error
    }
  }
}

///|
test "deterministic instruction tails stay in bounds across backends" {
  let mut seed = 29
  for _ in 0..<1024 {
    let bytes = Array::makei(2048, i => fixture_byte(i))
    let size = 1 + seed % 32
    let start = 2048 - size
    for i in start..<2048 {
      seed = (seed * 25173 + 13849) & 65535
      bytes[i] = (seed & 255).to_byte()
    }
    try {
      let instruction = @zvm.inspect_instruction(
        Bytes::from_array(bytes),
        start,
      )
      assert_eq(instruction.address, start)
      assert_true(
        instruction.next_address > start && instruction.next_address <= 2048,
      )
    } catch {
      @zvm.Invalid(_) => ()
      error => raise error
    }
  }
}

///|
fn fixture_byte(i : Int32) -> Byte {
  // Minimal valid v5 header; payload is supplied by the deterministic generator.
  (match i {
    0 => 5
    4 | 6 | 14 => 3
    8 => 2
    9 => 188
    10 => 2
    11 => 32
    13 => 64
    24 => 2
    25 => 128
    _ => 0
  }).to_byte()
}
