///|
test "random zero asks the host for a fresh seed" {
  let calls = [0]
  let m = @zvm.Machine::new(fixture(5, [0xe7, 0x7f, 0, 16, 186]), seed_source=fn() {
    calls[0] += 1
    calls[0]
  })
  assert_eq(calls[0], 1)
  assert_eq(m.run(), "halted")
  assert_eq(calls[0], 2)
}

///|
test "explicit negative seed reproduces output independently of initial entropy" {
  let story = fixture(5, [
    0xe7, 0x3f, 255, 249, 16, 0xe7, 0x7f, 100, 16, 0xe6, 0xbf, 16, 186,
  ])
  let a = @zvm.Machine::new(story, seed_source=fn() { 42 })
  let b = @zvm.Machine::new(story, seed_source=fn() { 65535 })
  assert_eq(a.run(), "halted")
  assert_eq(b.run(), "halted")
  assert_eq(a.take_output(), b.take_output())
}

///|
test "restart refreshes the host seed while preserving persistent flags" {
  let calls = [0]
  let code = [
    0x10, 0, 17, 16, 0xa0, 16, 0xc6, 0xe6, 0xbf, 16, 186, 0xe2, 0x57, 0, 17, 3, 183,
  ]
  let m = @zvm.Machine::new(fixture(5, code), seed_source=fn() {
    calls[0] += 1
    calls[0]
  })
  assert_eq(m.run(), "halted")
  assert_eq(calls[0], 2)
}

///|
test "invalid stories do not call the host seed source" {
  let calls = [0]
  let rejected = try {
    let _ = @zvm.Machine::new(b"", seed_source=fn() {
      calls[0] += 1
      1
    })
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
  assert_eq(calls[0], 0)
}
