///|
priv struct Instruction {
  form : Int32 // 0: 0OP, 1: 1OP, 2: 2OP, 3: VAR, 4: EXT
  opcode : Int32
  args : Array[Int32]
}

///|
fn Machine::operand(self : Machine, kind : Int32) -> Int32 raise Fault {
  match kind {
    0 => self.fetch() * 256 + self.fetch()
    1 => self.fetch()
    2 => self.variable(self.fetch())
    _ => raise Invalid("invalid operand type")
  }
}

///|
fn Machine::decode(self : Machine) -> Instruction raise Fault {
  let b = self.fetch()
  let args : Array[Int32] = []
  if b == 190 && self.version == 5 {
    let opcode = self.fetch()
    self.decode_types(self.fetch(), args)
    { form: 4, opcode, args, }
  } else if b < 128 {
    args.push(self.operand(if (b & 64) == 0 { 1 } else { 2 }))
    args.push(self.operand(if (b & 32) == 0 { 1 } else { 2 }))
    { form: 2, opcode: b & 31, args, }
  } else if b < 192 {
    let kind = (b >> 4) & 3
    if kind != 3 {
      args.push(self.operand(kind))
    }
    { form: if kind == 3 { 0 } else { 1 }, opcode: b & 15, args, }
  } else {
    let form = if (b & 32) == 0 { 2 } else { 3 }
    let opcode = b & 31
    let types = self.fetch()
    let second = if form == 3 && (opcode == 12 || opcode == 26) {
      self.fetch()
    } else {
      255
    }
    self.decode_types(types, args)
    if second != 255 {
      for shift in [6, 4, 2, 0] {
        if ((types >> shift) & 3) == 3 {
          raise Invalid("operand after omitted operand in second type byte")
        }
      }
      self.decode_types(second, args)
    }
    { form, opcode, args, }
  }
}

///|
fn Machine::decode_types(
  self : Machine,
  types : Int32,
  args : Array[Int32],
) -> Unit raise Fault {
  let mut omitted = false
  for shift in [6, 4, 2, 0] {
    let kind = (types >> shift) & 3
    if kind == 3 {
      omitted = true
    } else {
      if omitted {
        raise Invalid("operand after omitted operand")
      }
      args.push(self.operand(kind))
    }
  }
}
