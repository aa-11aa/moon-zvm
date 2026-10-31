///|
fn copy_frames(frames : Array[Frame]) -> Array[Frame] {
  frames.map(f => {
    locals: f.locals.copy(),
    stack: f.stack.copy(),
    return_pc: f.return_pc,
    store: f.store,
    argc: f.argc,
  })
}

///|
fn Machine::capture(self : Machine) -> Saved {
  {
    memory: Array::makei(self.static_base, i => self.mem[i]),
    frames: copy_frames(self.frames),
    pc: self.pc,
  }
}

///|
fn Machine::apply_saved(self : Machine, saved : Saved) -> Unit {
  // The transcript and fixed-pitch request bits survive restart and restore.
  let flags = self.mem[17] & 3
  for i in 0..<self.static_base {
    self.mem[i] = saved.memory[i]
  }
  self.mem[17] = (self.mem[17] & 252) | flags
  self.frames.clear()
  for f in copy_frames(saved.frames) {
    self.frames.push(f)
  }
  self.pc = saved.pc
  self.waiting = 0
  self.halted = false
}

///|
fn append_word(data : Array[Int32], value : Int32) -> Unit {
  data.push((value >> 8) & 255)
  data.push(value & 255)
}

///|
fn append_long(data : Array[Int32], value : Int32) -> Unit {
  append_word(data, value >> 16)
  append_word(data, value)
}

///|
fn append_id(data : Array[Int32], id : String) -> Unit {
  for c in id.to_array() {
    data.push(c.to_int())
  }
}

///|
fn append_chunk(
  data : Array[Int32],
  id : String,
  payload : Array[Int32],
) -> Unit {
  append_id(data, id)
  append_long(data, payload.length())
  for b in payload {
    data.push(b)
  }
  if payload.length() % 2 != 0 {
    data.push(0)
  }
}

///|
/// Produce an interoperable Quetzal IFZS save while run() reports "save".
/// Uses UMem (uncompressed dynamic memory) and standard Stks call frames.
pub fn Machine::save_data(self : Machine) -> Bytes raise Fault {
  if self.waiting != 3 {
    raise Invalid("no pending save request")
  }
  let header : Array[Int32] = []
  for i in [2, 3, 18, 19, 20, 21, 22, 23, 28, 29] {
    header.push(self.original[i].to_int())
  }
  header.push((self.pc >> 16) & 255)
  append_word(header, self.pc)
  let stack : Array[Int32] = []
  for i in 0..<self.frames.length() {
    let f = self.frames[i]
    let ret = if i == 0 { 0 } else { f.return_pc }
    stack.push((ret >> 16) & 255)
    append_word(stack, ret)
    stack.push(f.locals.length() | (if i > 0 && f.store < 0 { 16 } else { 0 }))
    stack.push(if f.store < 0 { 0 } else { f.store })
    stack.push((1 << f.argc) - 1)
    append_word(stack, f.stack.length())
    for v in f.locals {
      append_word(stack, v)
    }
    for v in f.stack {
      append_word(stack, v)
    }
  }
  let body : Array[Int32] = []
  append_id(body, "IFZS")
  append_chunk(body, "IFhd", header)
  append_chunk(body, "UMem", Array::makei(self.static_base, i => self.mem[i]))
  append_chunk(body, "Stks", stack)
  let data : Array[Int32] = []
  append_id(data, "FORM")
  append_long(data, body.length())
  for b in body {
    data.push(b)
  }
  Bytes::from_array(data.map(i => i.to_byte()))
}

///|
/// Tell the interpreter whether its host persisted the pending save.
pub fn Machine::finish_save(self : Machine, success : Bool) -> Unit raise Fault {
  if self.waiting != 3 {
    raise Invalid("no pending save request")
  }
  self.waiting = 0
  if self.version == 3 {
    self.branch(success)
  } else {
    self.store(if success { 1 } else { 0 })
  }
}

///|
/// Cancel an unavailable or declined restore operation.
pub fn Machine::cancel_restore(self : Machine) -> Unit raise Fault {
  if self.waiting != 4 {
    raise Invalid("no pending restore request")
  }
  self.waiting = 0
  if self.version == 3 {
    self.branch(false)
  } else {
    self.store(0)
  }
}

///|
priv struct SaveReader {
  bytes : Bytes
  mut pos : Int32
  limit : Int32
}

///|
fn SaveReader::byte(self : SaveReader) -> Int32 raise Fault {
  if self.pos < 0 || self.pos >= self.limit {
    raise Invalid("truncated Quetzal data")
  }
  let v = self.bytes[self.pos].to_int()
  self.pos += 1
  v
}

///|
fn SaveReader::word(self : SaveReader) -> Int32 raise Fault {
  self.byte() * 256 + self.byte()
}

///|
fn SaveReader::long(self : SaveReader) -> Int32 raise Fault {
  let hi = self.word()
  let lo = self.word()
  if hi >= 32768 {
    raise Invalid("oversized Quetzal chunk")
  }
  hi * 65536 + lo
}

///|
fn SaveReader::id(self : SaveReader) -> String raise Fault {
  let s = StringBuilder()
  for _ in 0..<4 {
    s.write_char(self.byte().unsafe_to_char())
  }
  s.to_string()
}

///|
/// Restore Quetzal CMem or UMem. The complete file is validated before changing state.
/// A rejected file leaves the pending restore available for cancellation or retry.
pub fn Machine::restore_data(self : Machine, data : Bytes) -> Unit raise Fault {
  if self.waiting != 4 {
    raise Invalid("no pending restore request")
  }
  let r = SaveReader::{ bytes: data, pos: 0, limit: data.length(), }
  if r.id() != "FORM" {
    raise Invalid("not an IFF FORM")
  }
  let length = r.long()
  if length != data.length() - 8 || r.id() != "IFZS" {
    raise Invalid("not a complete Quetzal FORM")
  }
  let mut pc = -1
  let mut memory : Array[Int32]? = None
  let mut frames : Array[Frame]? = None
  while r.pos < r.limit {
    let id = r.id()
    let size = r.long()
    if size > r.limit - r.pos {
      raise Invalid("truncated Quetzal chunk")
    }
    let end = r.pos + size
    let chunk = SaveReader::{ bytes: data, pos: r.pos, limit: end, }
    match id {
      "IFhd" => {
        if pc >= 0 || size < 13 {
          raise Invalid("invalid IFhd")
        }
        for i in [2, 3, 18, 19, 20, 21, 22, 23, 28, 29] {
          if chunk.byte() != self.original[i].to_int() {
            raise Invalid("save belongs to another story")
          }
        }
        pc = chunk.byte() * 65536 + chunk.word()
        if pc < 64 || pc >= self.mem.length() {
          raise Invalid("invalid saved PC")
        }
      }
      "UMem" | "CMem" => {
        if pc < 0 || memory is Some(_) {
          raise Invalid("invalid memory chunk order or duplicate")
        }
        let decoded = Array::makei(self.static_base, i => {
          self.original[i].to_int()
        })
        if id == "UMem" {
          if size != self.static_base {
            raise Invalid("wrong UMem size")
          }
          for i in 0..<self.static_base {
            decoded[i] = chunk.byte()
          }
        } else {
          let mut i = 0
          while chunk.pos < end {
            let value = chunk.byte()
            if value == 0 {
              i += chunk.byte() + 1
            } else {
              if i >= self.static_base {
                raise Invalid("CMem exceeds dynamic memory")
              }
              decoded[i] = decoded[i] ^ value
              i += 1
            }
            if i > self.static_base {
              raise Invalid("CMem run exceeds dynamic memory")
            }
          }
        }
        // Immutable header addresses must still match the current story.
        for i in [0, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 24, 25] {
          if decoded[i] != self.original[i].to_int() {
            raise Invalid("saved memory map differs")
          }
        }
        memory = Some(decoded)
      }
      "Stks" => {
        if pc < 0 || frames is Some(_) {
          raise Invalid("invalid stack chunk")
        }
        let decoded : Array[Frame] = []
        while chunk.pos < end {
          if decoded.length() >= 4096 {
            raise Invalid("too many saved call frames")
          }
          let ret = chunk.byte() * 65536 + chunk.word()
          let flags = chunk.byte()
          let dest = chunk.byte()
          let supplied = chunk.byte()
          let stack_count = chunk.word()
          if (flags & 224) != 0 || supplied > 127 {
            raise Invalid("invalid saved frame flags")
          }
          let locals : Array[Int32] = []
          let stack : Array[Int32] = []
          for _ in 0..<(flags & 15) {
            locals.push(chunk.word())
          }
          for _ in 0..<stack_count {
            stack.push(chunk.word())
          }
          if decoded.is_empty() {
            if ret != 0 || flags != 0 || dest != 0 || supplied != 0 {
              raise Invalid("invalid dummy frame")
            }
          } else if ret < 64 || ret >= self.mem.length() {
            raise Invalid("invalid saved return PC")
          }
          let mut argc = 0
          let mut bits = supplied
          while bits > 0 {
            argc += 1
            bits = bits >> 1
          }
          decoded.push({
            locals,
            stack,
            return_pc: ret,
            store: if decoded.is_empty() || (flags & 16) != 0 {
              -1
            } else {
              dest
            },
            argc,
          })
        }
        if decoded.is_empty() {
          raise Invalid("missing dummy frame")
        }
        frames = Some(decoded)
      }
      _ => ()
    }
    r.pos = end + size % 2
    if r.pos > r.limit {
      raise Invalid("missing IFF padding")
    }
  }
  match (memory, frames) {
    (Some(memory), Some(frames)) => {
      let saved = Saved::{ memory, frames, pc, }
      // Validate the resume store/branch on an isolated machine before committing.
      let preview = Machine::new(self.original)
      preview.apply_saved(saved)
      if self.version == 3 {
        preview.branch(true)
      } else {
        preview.store(2)
      }
      self.apply_saved(preview.capture())
      self.undo.clear()
    }
    _ => raise Invalid("missing required Quetzal chunks")
  }
}
