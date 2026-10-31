///|
fn fixture(version : Int32, code : Array[Int32]) -> Bytes {
  let data = Array::make(2048, b'\x00')
  data[0] = version.to_byte()
  for
    (addr, value) in [
      (4, 768),
      (6, 768),
      (8, 700),
      (10, 544),
      (12, 64),
      (14, 768),
      (24, 640),
    ] {
    data[addr] = (value >> 8).to_byte()
    data[addr + 1] = value.to_byte()
  }
  for i in 0..<code.length() {
    data[768 + i] = code[i].to_byte()
  }
  Bytes::from_array(data)
}

///|
fn output(version : Int32, code : Array[Int32]) -> String raise {
  let m = @zvm.Machine::new(fixture(version, code))
  assert_eq(m.run(), "halted")
  m.take_output()
}

///|
fn rejects(code : Array[Int32]) -> Unit raise {
  let m = @zvm.Machine::new(fixture(5, code))
  let rejected = try {
    let _ = m.run()
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "v3 and v5 literal text decoding" {
  for v in [3, 5] {
    // @print "abc" (Z-characters 6,7,8), @new_line, @quit.
    assert_eq(output(v, [178, 0x98, 0xe8, 187, 186]), "abc\n")
  }
}

///|
test "sixteen bit arithmetic wraps at stores" {
  // @add 65535 2 -> g0; @print_num g0; @quit.
  assert_eq(
    output(5, [0xd4, 0x0f, 255, 255, 0, 2, 16, 0xe6, 0xbf, 16, 186]),
    "1",
  )
}

///|
test "signed division truncates toward zero" {
  assert_eq(
    output(5, [0xd7, 0x0f, 255, 245, 0, 2, 16, 0xe6, 0xbf, 16, 186]),
    "-5",
  )
}

///|
test "signed remainder follows numerator" {
  assert_eq(
    output(5, [0xd8, 0x0f, 255, 243, 0, 5, 16, 0xe6, 0xbf, 16, 186]),
    "-3",
  )
}

///|
test "stack operands evaluate from left to right" {
  assert_eq(
    output(5, [
      0xe8, 0x7f, 2, 0xe8, 0x7f, 4, 0x75, 0, 0, 16, 0xe6, 0xbf, 16, 186,
    ]),
    "2",
  )
}

///|
test "indirect load peeks at stack" {
  assert_eq(
    output(5, [0xe8, 0x7f, 9, 0x9e, 0, 16, 0xe6, 0xbf, 16, 0xe6, 0xbf, 0, 186]),
    "99",
  )
}

///|
test "indirect store replaces stack top" {
  assert_eq(output(5, [0xe8, 0x7f, 9, 0x0d, 0, 7, 0xe6, 0xbf, 0, 186]), "7")
}

///|
test "logical shift zero fills while arithmetic preserves sign" {
  assert_eq(
    output(5, [
      190, 2, 0x0f, 255, 255, 255, 255, 16, 0xe6, 0xbf, 16, 190, 3, 0x0f, 255, 255,
      255, 255, 16, 0xe6, 0xbf, 16, 186,
    ]),
    "32767-1",
  )
}

///|
test "large array index wraps at sixteen bits" {
  // (base 64 + index 0x8000 * 2) wraps back to global 0.
  assert_eq(
    output(5, [0x0d, 16, 23, 0xcf, 0x0f, 0, 64, 128, 0, 17, 0xe6, 0xbf, 17, 186]),
    "23",
  )
}

///|
test "budget preserves execution position" {
  let m = @zvm.Machine::new(fixture(3, [180, 180, 186]))
  assert_eq(m.run(budget=1), "budget")
  assert_eq(m.position(), 769)
  assert_eq(m.run(budget=1), "budget")
  assert_eq(m.run(budget=1), "halted")
}

///|
test "zero budget makes no progress" {
  let m = @zvm.Machine::new(fixture(5, [186]))
  assert_eq(m.run(budget=0), "budget")
  assert_eq(m.position(), 768)
}

///|
test "v5 zero routine call stores zero" {
  assert_eq(output(5, [0x98, 0, 16, 0xe6, 0xbf, 16, 186]), "0")
}

///|
test "read_char suspends and resumes" {
  let m = @zvm.Machine::new(
    fixture(5, [0xf6, 0x7f, 1, 16, 0xe6, 0xbf, 16, 186]),
  )
  assert_eq(m.run(), "char")
  assert_eq(m.run(), "char")
  m.send_char(65)
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "65")
}

///|
test "memory stream captures number and text" {
  // stream 3 at 600; print -1; close stream; print stored length.
  assert_eq(
    output(5, [
      0xf3, 0x4f, 3, 2, 88, 0xe6, 0x3f, 255, 255, 0xf3, 0x3f, 255, 253, 0xcf, 0x1f,
      2, 88, 0, 16, 0xe6, 0xbf, 16, 186,
    ]),
    "2",
  )
}

///|
test "upper window captures text without lower transcript" {
  let m = @zvm.Machine::new(
    fixture(5, [0xea, 0x7f, 1, 0xeb, 0x7f, 1, 0xe5, 0x7f, 65, 186]),
  )
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "")
  assert_eq(m.upper_window().length(), 80)
  assert_eq(m.upper_window()[0].to_int(), 65)
}

///|
test "save restore resumes with value two and preserves state" {
  let m = @zvm.Machine::new(
    fixture(5, [190, 0, 255, 16, 0xe6, 0xbf, 16, 190, 1, 255, 17, 186]),
  )
  assert_eq(m.run(), "save")
  let save = m.save_data()
  m.finish_save(true)
  assert_eq(m.run(), "restore")
  assert_eq(m.take_output(), "1")
  m.restore_data(save)
  assert_eq(m.run(), "restore")
  assert_eq(m.take_output(), "2")
  m.cancel_restore()
  assert_eq(m.run(), "halted")
}

///|
test "v3 save restores branch point" {
  // @save ?+2, @print_char 'A', @restore ?+2, @quit.
  let m = @zvm.Machine::new(
    fixture(3, [181, 194, 0xe5, 0x7f, 65, 182, 194, 186]),
  )
  assert_eq(m.run(), "save")
  let data = m.save_data()
  m.finish_save(true)
  assert_eq(m.run(), "restore")
  assert_eq(m.take_output(), "A")
  m.restore_data(data)
  assert_eq(m.run(), "restore")
  assert_eq(m.take_output(), "A")
  m.cancel_restore()
  assert_eq(m.run(), "halted")
}

///|
test "rejected save prefixes do not change the waiting machine" {
  let m = @zvm.Machine::new(fixture(5, [190, 0, 255, 16, 190, 1, 255, 17, 186]))
  assert_eq(m.run(), "save")
  let data = m.save_data()
  m.finish_save(true)
  assert_eq(m.run(), "restore")
  let pos = m.position()
  for len in 0..<data.length() {
    let prefix = Bytes::from_array(Array::makei(len, i => data[i]))
    let rejected = try {
      m.restore_data(prefix)
      false
    } catch {
      @zvm.Invalid(_) => true
    }
    assert_true(rejected)
    assert_eq(m.position(), pos)
    assert_eq(m.run(), "restore")
  }
}

///|
test "division by zero reports Fault" {
  rejects([0x17, 1, 0, 16, 186])
}

///|
test "stack underflow reports Fault" {
  rejects([0xe6, 0xbf, 0, 186])
}

///|
test "missing local variable reports Fault" {
  rejects([0xe6, 0xbf, 1, 186])
}

///|
test "write to static memory reports Fault" {
  rejects([0xe2, 0x17, 3, 0, 0, 1, 186])
}

///|
test "unknown opcode reports Fault" {
  rejects([190, 255, 255])
}

///|
test "return from root reports Fault" {
  rejects([176])
}

///|
test "invalid object reports Fault" {
  rejects([0x93, 255, 16, 186])
}

///|
test "recursive abbreviation reports Fault" {
  rejects([178, 0x84, 0x05, 186])
}

///|
test "unsupported story versions reject" {
  for v in [0, 1, 2, 4, 6, 7, 8, 255] {
    let rejected = try {
      let _ = @zvm.Machine::new(fixture(v, [186]))
      false
    } catch {
      @zvm.Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "short story data reject without panic" {
  for len in 0..<64 {
    let rejected = try {
      let _ = @zvm.Machine::new(Bytes::from_array(Array::make(len, b'\x00')))
      false
    } catch {
      @zvm.Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "mutated bytecode is bounded or returns Fault" {
  for opcode in 0..<256 {
    let m = @zvm.Machine::new(fixture(5, [opcode, 0, 0, 0, 0, 0, 0, 0, 186]))
    try {
      let _ = m.run(budget=100)
    } catch {
      @zvm.Invalid(_) => ()
    }
  }
}

///|
test "restart preserves transcript and fixed-pitch header requests" {
  // Read Flags 2, set its persistent bits on the first pass, then restart.
  // The second pass must print 3 and halt instead of restarting forever.
  let code = [
    0x10, 0, 17, 16, 0xa0, 16, 0xc6, 0xe6, 0xbf, 16, 186, 0xe2, 0x57, 0, 17, 3, 183,
  ]
  for version in [3, 5] {
    assert_eq(output(version, code), "3")
  }
}
