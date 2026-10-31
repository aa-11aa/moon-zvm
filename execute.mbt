///|
/// Run up to `budget` instructions. Returns "halted", "line", "char", or "budget".
/// A budget prevents a hostile or looping story from monopolising its host.
pub fn Machine::run(
  self : Machine,
  budget~ : Int32 = 100000,
) -> String raise Fault {
  if budget < 0 {
    raise Invalid("negative instruction budget")
  }
  for _ in 0..<budget {
    if self.halted || self.waiting != 0 {
      break
    }
    let at = self.pc
    try {
      let instruction = self.decode()
      self.execute(instruction)
    } catch {
      Invalid(message) => raise Invalid("\{message} (instruction at \{at})")
    }
  }
  if self.halted {
    "halted"
  } else if self.waiting == 1 {
    "line"
  } else if self.waiting == 2 {
    "char"
  } else if self.waiting == 3 {
    "save"
  } else if self.waiting == 4 {
    "restore"
  } else {
    "budget"
  }
}

///|
fn Machine::execute(self : Machine, ins : Instruction) -> Unit raise Fault {
  let a = ins.args
  let x = if a.length() > 0 { a[0] } else { 0 }
  let y = if a.length() > 1 { a[1] } else { 0 }
  let z = if a.length() > 2 { a[2] } else { 0 }
  match ins.form {
    0 =>
      match ins.opcode {
        0 => self.ret(1)
        1 => self.ret(0)
        2 => self.pc = self.print_text(self.pc)
        3 => {
          self.pc = self.print_text(self.pc)
          self.emit(13)
          self.ret(1)
        }
        4 => ()
        5 | 6 => {
          if self.version != 3 {
            raise Invalid("v3 save opcode in v5")
          }
          self.waiting = if ins.opcode == 5 { 3 } else { 4 }
        }
        7 => self.restart()
        8 => self.ret(self.variable(0))
        9 =>
          if self.version == 3 {
            let _ = self.variable(0)
          } else {
            self.store(self.frames.length() - 1)
          }
        10 => self.halted = true
        11 => self.emit(13)
        12 => () // v3 status line belongs to the host screen model.
        13 => {
          let scale = if self.version == 3 { 2 } else { 4 }
          let n = (
              self.original[26].to_int() * 256 + self.original[27].to_int()
            ) *
            scale
          let mut sum = 0
          if n >= 64 && n <= self.original.length() {
            for i in 64..<n {
              sum = (sum + self.original[i].to_int()) & 65535
            }
          }
          let expected = self.original[28].to_int() * 256 +
            self.original[29].to_int()
          self.branch(n >= 64 && n <= self.original.length() && sum == expected)
        }
        15 => {
          if self.version != 5 {
            raise Invalid("piracy requires v5")
          }
          self.branch(true)
        }
        _ => raise Invalid("unknown 0OP opcode \{ins.opcode}")
      }
    1 => {
      if a.length() != 1 {
        raise Invalid("invalid 1OP operand count")
      }
      match ins.opcode {
        0 => self.branch(x == 0)
        1 | 2 => {
          let value = self.relation(x, if ins.opcode == 1 { 1 } else { 2 })
          self.store(value)
          self.branch(value != 0)
        }
        3 => self.store(self.relation(x, 0))
        4 => self.store(self.property_length(x))
        5 | 6 => {
          let value = self.variable(x, peek=true) +
            (if ins.opcode == 5 { 1 } else { -1 })
          self.assign(x, value, replace=true)
        }
        7 => {
          let _ = self.print_text(x)
        }
        8 => {
          if self.version != 5 {
            raise Invalid("call_1s requires v5")
          }
          self.call(a, true)
        }
        9 => self.remove_object(x)
        10 => {
          let table = self.property_table(x)
          if self.byte(table) != 0 {
            let _ = self.print_text(table + 1)
          }
        }
        11 => self.ret(x)
        12 => self.pc += signed(x) - 2
        13 => {
          let _ = self.print_text(x * (if self.version == 3 { 2 } else { 4 }))
        }
        14 => self.store(self.variable(x, peek=true))
        15 =>
          if self.version == 3 {
            self.store(x ^ 65535)
          } else {
            self.call(a, false)
          }
        _ => raise Invalid("unknown 1OP opcode")
      }
    }
    2 => {
      if a.length() < 2 || (ins.opcode != 1 && a.length() != 2) {
        raise Invalid("invalid 2OP operand count")
      }
      match ins.opcode {
        1 => {
          let mut same = false
          for i in 1..<a.length() {
            if x == a[i] {
              same = true
            }
          }
          self.branch(same)
        }
        2 => self.branch(signed(x) < signed(y))
        3 => self.branch(signed(x) > signed(y))
        4 | 5 => {
          let value = (
              self.variable(x, peek=true) +
              (if ins.opcode == 4 { -1 } else { 1 })
            ) &
            65535
          self.assign(x, value, replace=true)
          self.branch(
            if ins.opcode == 4 {
              signed(value) < signed(y)
            } else {
              signed(value) > signed(y)
            },
          )
        }
        6 => self.branch(self.relation(x, 0) == y)
        7 => self.branch((x & y) == y)
        8 => self.store(x | y)
        9 => self.store(x & y)
        10 => self.branch(self.attribute(x, y, 0))
        11 => {
          let _ = self.attribute(x, y, 1)
        }
        12 => {
          let _ = self.attribute(x, y, 2)
        }
        13 => self.assign(x, y, replace=true)
        14 => self.insert_object(x, y)
        15 => self.store(self.word((x + 2 * y) & 65535))
        16 => self.store(self.byte((x + y) & 65535))
        17 => self.store(self.get_property(x, y))
        18 => {
          let (data, _) = self.find_property(x, y)
          self.store(data)
        }
        19 => self.store(self.next_property(x, y))
        20 => self.store(x + y)
        21 => self.store(x - y)
        22 => self.store(signed(x) * signed(y))
        23 | 24 => {
          if y == 0 {
            raise Invalid("division by zero")
          }
          self.store(
            if ins.opcode == 23 {
              signed(x) / signed(y)
            } else {
              signed(x) % signed(y)
            },
          )
        }
        25 | 26 => {
          if self.version != 5 {
            raise Invalid("call_2 requires v5")
          }
          self.call(a, ins.opcode == 25)
        }
        27 => if self.version != 5 { raise Invalid("set_colour requires v5") }
        28 => {
          if self.version != 5 || y < 1 || y >= self.frames.length() {
            raise Invalid("invalid catch token")
          }
          while self.frames.length() > y + 1 {
            let _ = self.frames.pop()
          }
          self.ret(x)
        }
        _ => raise Invalid("unknown 2OP opcode \{ins.opcode}")
      }
    }
    3 =>
      match ins.opcode {
        0 | 12 | 25 | 26 => self.call(a, ins.opcode == 0 || ins.opcode == 12)
        1 => {
          self.require(a, 3)
          self.put_word((x + y * 2) & 65535, z)
        }
        2 => {
          self.require(a, 3)
          self.put_byte((x + y) & 65535, z)
        }
        3 => {
          self.require(a, 3)
          let (addr, size) = self.find_property(x, y)
          if addr == 0 || size > 2 {
            raise Invalid("put_prop requires existing one or two byte property")
          }
          if size == 1 {
            self.put_byte(addr, z)
          } else {
            self.put_word(addr, z)
          }
        }
        4 => {
          self.require(a, 2)
          if a.length() > 2 && z != 0 {
            raise Invalid("timed input not supported")
          }
          self.input_buffer = x
          self.parse_buffer = y
          self.input_store = if self.version == 5 { self.fetch() } else { -1 }
          self.waiting = 1
        }
        5 => {
          self.require(a, 1)
          self.emit(x)
        }
        6 => {
          self.require(a, 1)
          for c in signed(x).to_string().to_array() {
            self.emit(c.to_int())
          }
        }
        7 => {
          self.require(a, 1)
          let range = signed(x)
          if range <= 0 {
            self.rng = if range == 0 { 1 } else { -range }
            self.store(0)
          } else {
            self.rng = (self.rng * 25173 + 13849) & 65535
            self.store(self.rng % range + 1)
          }
        }
        8 => {
          self.require(a, 1)
          self.assign(0, x)
        }
        9 => {
          self.require(a, 1)
          let value = self.variable(0)
          self.assign(x, value, replace=true)
        }
        10 => {
          self.require(a, 1)
          self.split_window(x)
        }
        11 => {
          self.require(a, 1)
          self.select_window(x)
        }
        13 => {
          self.require(a, 1)
          self.erase_window(x)
        }
        14 => {
          self.require(a, 1)
          if x == 1 && self.window == 1 && self.rows[1] <= self.split {
            for col in (self.columns[1] - 1)..<80 {
              self.upper[(self.rows[1] - 1) * 80 + col] = 32
            }
          }
        }
        15 => {
          self.require(a, 2)
          if self.window == 1 {
            if x < 1 || x > self.split || y < 1 || y > 80 {
              raise Invalid("cursor outside upper window")
            }
            self.rows[1] = x
            self.columns[1] = y
          }
        }
        16 => {
          self.require(a, 1)
          self.put_word(x, self.rows[self.window])
          self.put_word(x + 2, self.columns[self.window])
        }
        17 | 18 => () // No styles are advertised in header Flags 1.
        19 => {
          self.require(a, 1)
          match signed(x) {
            1 => self.screen = true
            -1 => self.screen = false
            3 => {
              self.require(a, 2)
              if self.streams.length() >= 16 {
                raise Invalid("output stream nesting limit")
              }
              self.put_word(y, 0)
              self.streams.push(y)
            }
            -3 => {
              if self.streams.is_empty() {
                raise Invalid("unbalanced output stream 3")
              }
              let _ = self.streams.pop()
            }
            2 | -2 | 4 | -4 => ()
            _ => raise Invalid("invalid output stream")
          }
        }
        20 => {
          self.require(a, 1)
          if x != 0 {
            raise Invalid("file input stream unavailable")
          }
        }
        21 => ()
        22 => {
          self.require(a, 1)
          if x != 1 {
            raise Invalid("read_char requires keyboard device 1")
          }
          if a.length() > 1 && y != 0 {
            raise Invalid("timed character input unavailable")
          }
          self.input_store = self.fetch()
          self.waiting = 2
        }
        23 => {
          self.require(a, 3)
          let form = if a.length() >= 4 { a[3] } else { 0x82 }
          let size = form & 127
          if size == 0 {
            raise Invalid("scan_table has zero entry size")
          }
          let mut found = 0
          for i in 0..<z {
            let p = y + i * size
            let value = if (form & 128) != 0 {
              self.word(p)
            } else {
              self.byte(p)
            }
            if value == x {
              found = p
              break
            }
          }
          self.store(found)
          self.branch(found != 0)
        }
        24 => {
          self.require(a, 1)
          self.store(x ^ 65535)
        }
        27 => {
          self.require(a, 2)
          self.tokenise(
            x,
            y,
            if a.length() > 2 {
              z
            } else {
              0
            },
            a.length() > 3 && a[3] != 0,
          )
        }
        28 => {
          self.require(a, 4)
          let data = Array::makei(y, i => self.byte(x + z + i))
          self.encode_dictionary(data, a[3])
        }
        29 => {
          self.require(a, 3)
          let n = signed(z)
          let count = if n < 0 { -n } else { n }
          if y == 0 {
            for i in 0..<count {
              self.put_byte(x + i, 0)
            }
          } else if n < 0 || y <= x {
            for i in 0..<count {
              self.put_byte(y + i, self.byte(x + i))
            }
          } else {
            for i = count - 1; i >= 0; i = i - 1 {
              self.put_byte(y + i, self.byte(x + i))
            }
          }
        }
        30 => {
          self.require(a, 2)
          let height = if a.length() >= 3 { z } else { 1 }
          let skip = if a.length() >= 4 { a[3] } else { 0 }
          for row in 0..<height {
            if row > 0 {
              self.emit(13)
            }
            for col in 0..<y {
              self.emit(self.byte(x + row * (y + skip) + col))
            }
          }
        }
        31 => {
          self.require(a, 1)
          self.branch(self.frame().argc >= x)
        }
        _ => raise Invalid("unknown VAR opcode \{ins.opcode}")
      }
    4 =>
      match ins.opcode {
        0 | 1 =>
          if a.is_empty() {
            self.waiting = if ins.opcode == 0 { 3 } else { 4 }
          } else {
            self.store(0)
          } // Auxiliary files are not available through this host API.
        9 => {
          if self.undo.length() >= 16 {
            self.undo.remove(0) |> ignore
          }
          self.undo.push(self.capture())
          self.store(1)
        }
        10 =>
          if self.undo.is_empty() {
            self.store(0)
          } else {
            self.apply_saved(self.undo.pop().unwrap())
            self.store(2)
          }
        2 | 3 => {
          self.require(a, 2)
          let shift = signed(y)
          let value = if ins.opcode == 2 { x } else { signed(x) }
          self.store(
            if shift >= 16 {
              0
            } else if shift <= -16 {
              if value < 0 {
                -1
              } else {
                0
              }
            } else if shift >= 0 {
              value << shift
            } else {
              value >> -shift
            },
          )
        }
        4 => {
          self.require(a, 1)
          let old = self.font
          if x == 0 {
            self.store(old)
          } else if x == 1 || x == 4 {
            self.font = x
            self.store(old)
          } else {
            self.store(0)
          }
        }
        11 => {
          self.require(a, 1)
          if x >= 0xd800 && x <= 0xdfff {
            raise Invalid("surrogate Unicode character")
          }
          self.display_char(x)
        }
        12 => {
          self.require(a, 1)
          self.store(if x >= 32 && x < 0xd800 { 3 } else { 0 })
        }
        13 => ()
        _ => raise Invalid("unsupported EXT opcode \{ins.opcode}")
      }
    _ => raise Invalid("invalid instruction form")
  }
}

///|
fn Machine::require(
  _self : Machine,
  args : Array[Int32],
  count : Int32,
) -> Unit raise Fault {
  if args.length() < count {
    raise Invalid("missing instruction operands")
  }
}

///|
fn Machine::restart(self : Machine) -> Unit raise Fault {
  let fresh = Machine::new(self.original)
  for i in 0..<self.static_base {
    self.mem[i] = fresh.mem[i]
  }
  self.frames.clear()
  self.frames.push(fresh.frames[0])
  self.pc = fresh.pc
  self.waiting = 0
  self.streams.clear()
  self.undo.clear()
  self.screen = true
  self.upper.fill(32)
  self.rows.fill(1)
  self.columns.fill(1)
  self.window = 0
  self.split = 0
}
