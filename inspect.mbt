///|
pub struct OperandInfo {
  kind : String
  value : Int32
}

///|
pub struct BranchInfo {
  on_true : Bool
  offset : Int32
  target : Int32?
  return_value : Int32?
}

///|
pub struct InstructionInfo {
  address : Int32
  next_address : Int32
  form : String
  opcode : Int32
  mnemonic : String
  operands : Array[OperandInfo]
  store : Int32?
  branch : BranchInfo?
  inline_text : Int32?
}

///|
priv enum CodeSource {
  Story(Bytes)
  Live(Array[Int32])
}

///|
priv struct CodeCursor {
  source : CodeSource
  mut pc : Int32
}

///|
fn CodeCursor::fetch(self : CodeCursor) -> Int32 raise Fault {
  let length = match self.source {
    Story(b) => b.length()
    Live(m) => m.length()
  }
  if self.pc < 64 || self.pc >= length {
    raise Invalid("instruction read outside story at \{self.pc}")
  }
  let value = match self.source {
    Story(b) => b[self.pc].to_int()
    Live(m) => m[self.pc]
  }
  self.pc += 1
  value
}

///|
fn CodeCursor::word(self : CodeCursor) -> Int32 raise Fault {
  self.fetch() * 256 + self.fetch()
}

// Metadata is deliberately independent of operand values: inspection never reads
// a local/global variable or pops the evaluation stack.

///|
fn opcode_info(
  version : Int32,
  form : Int32,
  op : Int32,
) -> (String, Bool, Bool, Bool, Int32, Int32) raise Fault {
  let mut store = false
  let mut branch = false
  let mut text = false
  let mut min = 0
  let mut max = 0
  let name = match form {
    0 =>
      match op {
        0 => "rtrue"
        1 => "rfalse"
        2 => {
          text = true
          "print"
        }
        3 => {
          text = true
          "print_ret"
        }
        4 => "nop"
        5 | 6 => {
          if version != 3 {
            raise Invalid("v3 save/restore opcode in v5")
          }
          branch = true
          if op == 5 {
            "save"
          } else {
            "restore"
          }
        }
        7 => "restart"
        8 => "ret_popped"
        9 => {
          store = version == 5
          if version == 5 {
            "catch"
          } else {
            "pop"
          }
        }
        10 => "quit"
        11 => "new_line"
        12 => {
          if version != 3 {
            raise Invalid("show_status requires v3")
          }
          "show_status"
        }
        13 => {
          branch = true
          "verify"
        }
        15 => {
          if version != 5 {
            raise Invalid("piracy requires v5")
          }
          branch = true
          "piracy"
        }
        _ => raise Invalid("unknown 0OP opcode")
      }
    1 => {
      min = 1
      max = 1
      match op {
        0 => {
          branch = true
          "jz"
        }
        1 | 2 => {
          store = true
          branch = true
          if op == 1 {
            "get_sibling"
          } else {
            "get_child"
          }
        }
        3 => {
          store = true
          "get_parent"
        }
        4 => {
          store = true
          "get_prop_len"
        }
        5 => "inc"
        6 => "dec"
        7 => "print_addr"
        8 => {
          if version != 5 {
            raise Invalid("call_1s requires v5")
          }
          store = true
          "call_1s"
        }
        9 => "remove_obj"
        10 => "print_obj"
        11 => "ret"
        12 => "jump"
        13 => "print_paddr"
        14 => {
          store = true
          "load"
        }
        15 => {
          store = version == 3
          if version == 3 {
            "not"
          } else {
            "call_1n"
          }
        }
        _ => raise Invalid("unknown 1OP opcode")
      }
    }
    2 => {
      min = 2
      max = if op == 1 { 4 } else { 2 }
      if op >= 25 && version != 5 {
        raise Invalid("2OP instruction requires v5")
      }
      if (op >= 1 && op <= 7) || op == 10 {
        branch = true
      }
      if op == 8 || op == 9 || (op >= 15 && op <= 25) {
        store = true
      }
      match op {
        1 => "je"
        2 => "jl"
        3 => "jg"
        4 => "dec_chk"
        5 => "inc_chk"
        6 => "jin"
        7 => "test"
        8 => "or"
        9 => "and"
        10 => "test_attr"
        11 => "set_attr"
        12 => "clear_attr"
        13 => "store"
        14 => "insert_obj"
        15 => "loadw"
        16 => "loadb"
        17 => "get_prop"
        18 => "get_prop_addr"
        19 => "get_next_prop"
        20 => "add"
        21 => "sub"
        22 => "mul"
        23 => "div"
        24 => "mod"
        25 => "call_2s"
        26 => "call_2n"
        27 => "set_colour"
        28 => "throw"
        _ => raise Invalid("unknown 2OP opcode")
      }
    }
    3 => {
      if version == 3 && op >= 12 && op != 19 && op != 20 && op != 21 {
        raise Invalid("VAR instruction requires v5")
      }
      min = 1
      max = 1
      match op {
        0 => {
          store = true
          max = 4
          if version == 3 {
            "call"
          } else {
            "call_vs"
          }
        }
        1 => {
          min = 3
          max = 3
          "storew"
        }
        2 => {
          min = 3
          max = 3
          "storeb"
        }
        3 => {
          min = 3
          max = 3
          "put_prop"
        }
        4 => {
          min = 2
          max = if version == 3 { 2 } else { 4 }
          store = version == 5
          if version == 3 {
            "sread"
          } else {
            "aread"
          }
        }
        5 => "print_char"
        6 => "print_num"
        7 => {
          store = true
          "random"
        }
        8 => "push"
        9 => "pull"
        10 => "split_window"
        11 => "set_window"
        12 => {
          max = 8
          store = true
          "call_vs2"
        }
        13 => "erase_window"
        14 => "erase_line"
        15 => {
          min = 2
          max = 2
          "set_cursor"
        }
        16 => "get_cursor"
        17 => "set_text_style"
        18 => "buffer_mode"
        19 => {
          max = 2
          "output_stream"
        }
        20 => "input_stream"
        21 => {
          max = 4
          "sound_effect"
        }
        22 => {
          max = 3
          store = true
          "read_char"
        }
        23 => {
          min = 3
          max = 4
          store = true
          branch = true
          "scan_table"
        }
        24 => {
          store = true
          "not"
        }
        25 => {
          max = 4
          "call_vn"
        }
        26 => {
          max = 8
          "call_vn2"
        }
        27 => {
          min = 2
          max = 4
          "tokenise"
        }
        28 => {
          min = 4
          max = 4
          "encode_text"
        }
        29 => {
          min = 3
          max = 3
          "copy_table"
        }
        30 => {
          min = 2
          max = 4
          "print_table"
        }
        31 => {
          branch = true
          "check_arg_count"
        }
        _ => raise Invalid("unknown VAR opcode")
      }
    }
    4 => {
      if version != 5 {
        raise Invalid("extended instruction requires v5")
      }
      match op {
        0 => {
          max = 4
          store = true
          "save"
        }
        1 => {
          max = 4
          store = true
          "restore"
        }
        2 => {
          min = 2
          max = 2
          store = true
          "log_shift"
        }
        3 => {
          min = 2
          max = 2
          store = true
          "art_shift"
        }
        4 => {
          min = 1
          max = 2
          store = true
          "set_font"
        }
        9 => {
          store = true
          "save_undo"
        }
        10 => {
          store = true
          "restore_undo"
        }
        11 => {
          min = 1
          max = 1
          "print_unicode"
        }
        12 => {
          min = 1
          max = 1
          store = true
          "check_unicode"
        }
        13 => {
          min = 2
          max = 2
          "set_true_colour"
        }
        _ => raise Invalid("unsupported extended instruction")
      }
    }
    _ => raise Invalid("unknown instruction form")
  }
  (name, store, branch, text, min, max)
}

///|
fn append_types(types : Int32, kinds : Array[Int32]) -> Unit raise Fault {
  let mut omitted = !kinds.is_empty() && kinds[kinds.length() - 1] == 3
  for shift in [6, 4, 2, 0] {
    let kind = (types >> shift) & 3
    if kind == 3 {
      omitted = true
    } else if omitted {
      raise Invalid("operand after omitted operand")
    }
    kinds.push(kind)
  }
}

///|
fn inspect_cursor(
  cursor : CodeCursor,
  version : Int32,
) -> InstructionInfo raise Fault {
  let address = cursor.pc
  let b = cursor.fetch()
  let kinds : Array[Int32] = []
  let (form, op) = if b == 190 && version == 5 {
    let op = cursor.fetch()
    append_types(cursor.fetch(), kinds)
    (4, op)
  } else if b < 128 {
    kinds.push(if (b & 64) == 0 { 1 } else { 2 })
    kinds.push(if (b & 32) == 0 { 1 } else { 2 })
    (2, b & 31)
  } else if b < 192 {
    let kind = (b >> 4) & 3
    if kind != 3 {
      kinds.push(kind)
    }
    (if kind == 3 { 0 } else { 1 }, b & 15)
  } else {
    let form = if (b & 32) == 0 { 2 } else { 3 }
    let op = b & 31
    append_types(cursor.fetch(), kinds)
    if form == 3 && (op == 12 || op == 26) {
      append_types(cursor.fetch(), kinds)
    }
    (form, op)
  }
  let (mnemonic, has_store, has_branch, has_text, min, max) = opcode_info(
    version, form, op,
  )
  let operands : Array[OperandInfo] = []
  for kind in kinds {
    if kind == 3 {
      break
    }
    let value = if kind == 0 { cursor.word() } else { cursor.fetch() }
    operands.push({
      kind: if kind == 0 {
        "large"
      } else if kind == 1 {
        "small"
      } else {
        "variable"
      },
      value,
    })
  }
  if operands.length() < min || operands.length() > max {
    raise Invalid("invalid operand count")
  }
  let store = if has_store { Some(cursor.fetch()) } else { None }
  let branch = if has_branch {
    let first = cursor.fetch()
    let offset = if (first & 64) != 0 {
      first & 63
    } else {
      let n = ((first & 63) << 8) | cursor.fetch()
      if (n & 8192) != 0 {
        n - 16384
      } else {
        n
      }
    }
    let returns = offset == 0 || offset == 1
    Some(BranchInfo::{
      on_true: (first & 128) != 0,
      offset,
      target: if returns {
        None
      } else {
        Some(cursor.pc + offset - 2)
      },
      return_value: if returns {
        Some(offset)
      } else {
        None
      },
    })
  } else {
    None
  }
  let inline_text = if has_text {
    let start = cursor.pc
    while (cursor.word() & 32768) == 0 {

    }
    Some(start)
  } else {
    None
  }
  {
    address,
    next_address: cursor.pc,
    form: match form {
      0 => "0OP"
      1 => "1OP"
      2 => "2OP"
      3 => "VAR"
      _ => "EXT"
    },
    opcode: op,
    mnemonic,
    operands,
    store,
    branch,
    inline_text,
  }
}

///|
/// Decode one raw instruction. Variable operands are reported by reference, not evaluated.
pub fn inspect_instruction(
  story : Bytes,
  address : Int32,
) -> InstructionInfo raise Fault {
  let info = inspect_story(story)
  inspect_cursor({ source: Story(story), pc: address, }, info.version)
}

///|
/// Decode the next live instruction without changing PC, memory, output or stacks.
pub fn Machine::peek_instruction(self : Machine) -> InstructionInfo raise Fault {
  if self.halted || self.waiting != 0 {
    raise Invalid(
      "no executable instruction while halted or waiting for the host",
    )
  }
  inspect_cursor({ source: Live(self.mem), pc: self.pc, }, self.version)
}

///|
fn variable_name(value : Int32) -> String {
  if value == 0 {
    "sp"
  } else if value < 16 {
    "l\{value}"
  } else {
    "g\{value-16}"
  }
}

///|
/// Human-readable raw disassembly, safe for use in terminals.
pub fn InstructionInfo::format(self : InstructionInfo) -> String {
  let out = StringBuilder()
  out.write_string("\{self.address}: \{self.mnemonic}")
  for operand in self.operands {
    out.write_string(" ")
    out.write_string(
      if operand.kind == "variable" {
        variable_name(operand.value)
      } else {
        operand.value.to_string()
      },
    )
  }
  if self.store is Some(v) {
    out.write_string(" -> \{variable_name(v)}")
  }
  if self.branch is Some(b) {
    out.write_string(if b.on_true { " ?true " } else { " ?false " })
    if b.return_value is Some(v) {
      out.write_string("return=\{v}")
    }
    if b.target is Some(v) {
      out.write_string("target=\{v}")
    }
  }
  if self.inline_text is Some(v) {
    out.write_string(" text@\{v}")
  }
  out.to_string()
}
