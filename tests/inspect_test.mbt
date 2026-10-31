///|
test "raw variable operands do not need a live stack" {
  let info = @zvm.inspect_instruction(fixture(5, [0x75, 0, 0, 16]), 768)
  assert_eq(info.mnemonic, "sub")
  assert_eq(info.operands[0].kind, "variable")
  assert_eq(info.operands[0].value, 0)
  assert_eq(info.store, Some(16))
  assert_eq(info.next_address, 772)
  assert_eq(info.format(), "768: sub sp sp -> g0")
}

///|
test "inspection identifies inline text boundary" {
  let info = @zvm.inspect_instruction(fixture(3, [178, 0x98, 0xe8, 186]), 768)
  assert_eq(info.inline_text, Some(769))
  assert_eq(info.next_address, 771)
}

///|
test "short branches can return from the current routine" {
  let info = @zvm.inspect_instruction(fixture(5, [0x90, 0, 0xc1]), 768)
  let branch = info.branch.unwrap()
  assert_true(branch.on_true)
  assert_eq(branch.return_value, Some(1))
  assert_eq(branch.target, None)
}

///|
test "signed long branch target follows the standard offset formula" {
  let info = @zvm.inspect_instruction(fixture(5, [0x90, 0, 0xbf, 0xfc]), 768)
  assert_eq(info.branch.unwrap().offset, -4)
  assert_eq(info.branch.unwrap().target, Some(766))
}

///|
test "extended and double-variable instructions retain raw operands" {
  let ext = @zvm.inspect_instruction(
    fixture(5, [190, 2, 0x0f, 0, 4, 255, 255, 16]),
    768,
  )
  assert_eq(ext.form, "EXT")
  assert_eq(ext.mnemonic, "log_shift")
  assert_eq(ext.next_address, 776)
  let call = @zvm.inspect_instruction(
    fixture(5, [0xec, 0x55, 0x7f, 1, 2, 3, 4, 5, 16]),
    768,
  )
  assert_eq(call.mnemonic, "call_vs2")
  assert_eq(call.operands.length(), 5)
  assert_eq(call.next_address, 777)
}

///|
test "omitted operands remain omitted across both type bytes" {
  let rejected = try {
    let _ = @zvm.inspect_instruction(
      fixture(5, [0xec, 0x7f, 0x7f, 1, 2, 16]),
      768,
    )
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "live peek preserves PC and evaluation stack" {
  let m = @zvm.Machine::new(fixture(5, [0xe8, 0x7f, 9, 0xe6, 0xbf, 0, 186]))
  assert_eq(m.run(budget=1), "budget")
  let at = m.position()
  assert_eq(m.peek_instruction().format(), "771: print_num sp")
  assert_eq(m.peek_instruction().address, at)
  assert_eq(m.position(), at)
  assert_eq(m.run(), "halted")
  assert_eq(m.take_output(), "9")
}

///|
test "peek refuses host-waiting states without advancing" {
  let m = @zvm.Machine::new(fixture(5, [0xf6, 0x7f, 1, 16, 186]))
  assert_eq(m.run(), "char")
  let at = m.position()
  let rejected = try {
    let _ = m.peek_instruction()
    false
  } catch {
    @zvm.Invalid(_) => true
  }
  assert_true(rejected)
  assert_eq(m.position(), at)
}

///|
test "instruction versions and missing operands are checked" {
  for code in [[0x98, 1, 16], [190, 255, 255], [0xd4, 255, 16]] {
    let rejected = try {
      let _ = @zvm.inspect_instruction(fixture(3, code), 768)
      false
    } catch {
      @zvm.Invalid(_) => true
    }
    assert_true(rejected)
  }
}
