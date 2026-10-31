///|
/// Errors in story data or execution are reported rather than indexing unchecked memory.
pub(all) suberror Fault {
  Invalid(String)
}

///|
/// A resumable interpreter. File and terminal I/O belong to the embedding host.
struct Machine {
  mem : Array[Int32]
  original : Bytes
  version : Int32
  static_base : Int32
  globals : Int32
  objects : Int32
  abbreviations : Int32
  mut pc : Int32
  frames : Array[Frame]
  mut output : StringBuilder
  mut halted : Bool
  mut waiting : Int32
  mut input_buffer : Int32
  mut parse_buffer : Int32
  mut input_store : Int32
  mut rng : Int32
  seed_source : () -> Int32
  streams : Array[Int32]
  mut screen : Bool
  undo : Array[Saved]
  upper : Array[Int32]
  rows : Array[Int32]
  columns : Array[Int32]
  mut window : Int32
  mut split : Int32
  mut font : Int32
  mut output_count : Int32
}

///|
priv struct Saved {
  memory : Array[Int32]
  frames : Array[Frame]
  pc : Int32
}

///|
priv struct Frame {
  locals : Array[Int32]
  stack : Array[Int32]
  return_pc : Int32
  store : Int32
  argc : Int32
}

///|
/// Load a raw v3 or v5 story. Blorb containers must be extracted by the host.
/// Hosts can provide fresh seeds for normal play and @random 0. The default
/// seed source is deterministic for reproducible embedding and tests.
pub fn Machine::new(
  story : Bytes,
  seed_source~ : () -> Int32 = fn() { 1 },
) -> Machine raise Fault {
  let info = inspect_story(story)
  let mem = Array::makei(story.length(), i => story[i].to_int())
  let version = info.version
  let static_base = info.static_memory
  let globals = info.globals
  let objects = info.objects
  let pc = info.initial_pc
  let m = Machine::{
    mem,
    original: story,
    version,
    static_base,
    globals,
    objects,
    abbreviations: info.abbreviations,
    pc,
    frames: [{ locals: [], stack: [], return_pc: 0, store: -1, argc: 0, }],
    output: StringBuilder(),
    halted: false,
    waiting: 0,
    input_buffer: 0,
    parse_buffer: 0,
    input_store: -1,
    rng: seed_source() & 65535,
    seed_source,
    streams: [],
    screen: true,
    undo: [],
    upper: Array::make(2000, 32),
    rows: [1, 1],
    columns: [1, 1],
    window: 0,
    split: 0,
    font: 1,
    output_count: 0,
  }
  // Advertise only implemented capabilities. No timed input, sound, graphics or mouse.
  m.mem[1] = if version == 3 { (m.mem[1] & 0x8f) | 0x30 } else { 0 }
  m.mem[16] = m.mem[16] & 0x01
  m.mem[17] = m.mem[17] & 0x53
  m.mem[30] = 6
  m.mem[31] = 65
  m.mem[32] = 25
  m.mem[33] = 80
  m.mem[34] = 0
  m.mem[35] = 80
  m.mem[36] = 0
  m.mem[37] = 25
  m.mem[38] = 1
  m.mem[39] = 1
  m.mem[44] = 2
  m.mem[45] = 9
  // Standard revision stays zero until full conformance has been established.
  m.mem[50] = 0
  m.mem[51] = 0
  m
}

///|
fn Machine::byte(self : Machine, addr : Int32) -> Int32 raise Fault {
  if addr < 0 || addr >= self.mem.length() {
    raise Invalid("read outside story at \{addr}")
  }
  self.mem[addr]
}

///|
fn Machine::word(self : Machine, addr : Int32) -> Int32 raise Fault {
  let hi = self.byte(addr)
  hi * 256 + self.byte(addr + 1)
}

///|
fn Machine::put_byte(
  self : Machine,
  addr : Int32,
  value : Int32,
) -> Unit raise Fault {
  if addr < 0 || addr >= self.static_base {
    raise Invalid("write outside dynamic memory at \{addr}")
  }
  self.mem[addr] = value & 255
}

///|
fn Machine::put_word(
  self : Machine,
  addr : Int32,
  value : Int32,
) -> Unit raise Fault {
  if addr < 0 || addr >= self.static_base - 1 {
    raise Invalid("word write outside dynamic memory")
  }
  self.mem[addr] = (value >> 8) & 255
  self.mem[addr + 1] = value & 255
}

///|
fn Machine::fetch(self : Machine) -> Int32 raise Fault {
  let value = self.byte(self.pc)
  self.pc += 1
  value
}

///|
fn signed(value : Int32) -> Int32 {
  if (value & 32768) != 0 {
    (value & 65535) - 65536
  } else {
    value & 65535
  }
}

///|
fn Machine::frame(self : Machine) -> Frame {
  self.frames[self.frames.length() - 1]
}

///|
fn Machine::variable(
  self : Machine,
  number : Int32,
  peek~ : Bool = false,
) -> Int32 raise Fault {
  let f = self.frame()
  if number == 0 {
    if f.stack.is_empty() {
      raise Invalid("evaluation stack underflow")
    }
    if peek {
      f.stack[f.stack.length() - 1]
    } else {
      f.stack.pop().unwrap()
    }
  } else if number < 16 {
    if number < 0 || number > f.locals.length() {
      raise Invalid("invalid local variable")
    }
    f.locals[number - 1]
  } else {
    if number > 255 {
      raise Invalid("invalid global variable")
    }
    self.word(self.globals + 2 * (number - 16))
  }
}

///|
fn Machine::assign(
  self : Machine,
  number : Int32,
  value : Int32,
  replace~ : Bool = false,
) -> Unit raise Fault {
  let f = self.frame()
  let value = value & 65535
  if number == 0 {
    if replace {
      if f.stack.is_empty() {
        raise Invalid("evaluation stack underflow")
      }
      f.stack[f.stack.length() - 1] = value
    } else {
      if f.stack.length() >= 65536 {
        raise Invalid("evaluation stack limit")
      }
      f.stack.push(value)
    }
  } else if number < 16 {
    if number < 0 || number > f.locals.length() {
      raise Invalid("invalid local variable")
    }
    f.locals[number - 1] = value
  } else {
    if number > 255 {
      raise Invalid("invalid global variable")
    }
    self.put_word(self.globals + 2 * (number - 16), value)
  }
}

///|
fn Machine::store(self : Machine, value : Int32) -> Unit raise Fault {
  let dest = self.fetch()
  self.assign(dest, value)
}

///|
fn Machine::ret(self : Machine, value : Int32) -> Unit raise Fault {
  if self.frames.length() == 1 {
    raise Invalid("return from initial execution context")
  }
  let f = self.frames.pop().unwrap()
  self.pc = f.return_pc
  if f.store >= 0 {
    self.assign(f.store, value)
  }
}

///|
fn Machine::branch(self : Machine, condition : Bool) -> Unit raise Fault {
  let b = self.fetch()
  let offset = if (b & 64) != 0 {
    b & 63
  } else {
    let n = ((b & 63) << 8) | self.fetch()
    if (n & 8192) != 0 {
      n - 16384
    } else {
      n
    }
  }
  if condition == ((b & 128) != 0) {
    if offset <= 1 && offset >= 0 {
      self.ret(offset)
    } else {
      self.pc += offset - 2
    }
  }
}

///|
fn Machine::call(
  self : Machine,
  args : Array[Int32],
  stores : Bool,
) -> Unit raise Fault {
  if args.is_empty() {
    raise Invalid("call without routine")
  }
  let dest = if stores { self.fetch() } else { -1 }
  if args[0] == 0 {
    if dest >= 0 {
      self.assign(dest, 0)
    }
    return
  }
  if self.frames.length() >= 4096 {
    raise Invalid("call stack limit")
  }
  let return_pc = self.pc
  self.pc = args[0] * (if self.version == 3 { 2 } else { 4 })
  let count = self.fetch()
  if count > 15 {
    raise Invalid("invalid routine local count")
  }
  let locals = Array::make(count, 0)
  for i in 0..<count {
    if self.version == 3 {
      locals[i] = self.fetch() * 256 + self.fetch()
    }
    if i + 1 < args.length() {
      locals[i] = args[i + 1]
    }
  }
  self.frames.push({
    locals,
    stack: [],
    return_pc,
    store: dest,
    argc: args.length() - 1,
  })
}

///|
/// Take buffered text without advancing the interpreter.
pub fn Machine::take_output(self : Machine) -> String {
  let result = self.output.to_string()
  self.output = StringBuilder()
  self.output_count = 0
  result
}

///|
/// Inspect execution position for diagnostics.
pub fn Machine::position(self : Machine) -> Int32 {
  self.pc
}

///|
/// True after @quit.
pub fn Machine::is_halted(self : Machine) -> Bool {
  self.halted
}
