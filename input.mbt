///|
fn Machine::dictionary_key(
  self : Machine,
  text : Array[Int32],
) -> Array[Int32] raise Fault {
  let count = if self.version == 3 { 6 } else { 9 }
  let zs : Array[Int32] = []
  let custom = if self.version == 5 { self.word(52) } else { 0 }
  for code in text {
    if zs.length() >= count {
      break
    }
    if code == 32 {
      zs.push(0)
      continue
    }
    let mut found = false
    for alphabet in 0..<3 {
      for idx in 0..<26 {
        if alphabet == 2 && idx == 0 {
          continue
        }
        let value = if custom != 0 {
          self.byte(custom + alphabet * 26 + idx)
        } else if alphabet == 0 {
          97 + idx
        } else if alphabet == 1 {
          65 + idx
        } else if idx == 1 {
          13
        } else {
          "0123456789.,!?_#'\"/\\-:()"[idx - 2].to_int()
        }
        if value == code {
          if alphabet != 0 {
            zs.push(alphabet + 3)
          }
          zs.push(idx + 6)
          found = true
          break
        }
      }
      if found {
        break
      }
    }
    if !found {
      zs.push(5)
      zs.push(6)
      zs.push((code >> 5) & 31)
      zs.push(code & 31)
    }
  }
  while zs.length() < count {
    zs.push(5)
  }
  let result : Array[Int32] = []
  for i in 0..<(count / 3) {
    let w = (zs[i * 3] << 10) |
      (zs[i * 3 + 1] << 5) |
      zs[i * 3 + 2] |
      (if i == count / 3 - 1 { 32768 } else { 0 })
    result.push(w >> 8)
    result.push(w & 255)
  }
  result
}

///|
fn Machine::encode_dictionary(
  self : Machine,
  data : Array[Int32],
  destination : Int32,
) -> Unit raise Fault {
  let key = self.dictionary_key(data)
  for i in 0..<key.length() {
    self.put_byte(destination + i, key[i])
  }
}

///|
fn Machine::lookup(
  self : Machine,
  text : Array[Int32],
  dictionary : Int32,
) -> Int32 raise Fault {
  let key = self.dictionary_key(text)
  let count = self.byte(dictionary)
  let stride = self.byte(dictionary + 1 + count)
  let raw = signed(self.word(dictionary + 2 + count))
  let entries = if raw < 0 { -raw } else { raw }
  let base = dictionary + 4 + count
  if stride < key.length() {
    raise Invalid("dictionary entries too short")
  }
  if entries > (self.mem.length() - base) / stride {
    raise Invalid("truncated dictionary")
  }
  // A linear lookup also handles unsorted user dictionaries without trusting their order.
  for i in 0..<entries {
    let addr = base + i * stride
    let mut same = true
    for j in 0..<key.length() {
      if self.byte(addr + j) != key[j] {
        same = false
        break
      }
    }
    if same {
      return addr
    }
  }
  0
}

///|
fn Machine::tokenise(
  self : Machine,
  buffer : Int32,
  parse : Int32,
  custom : Int32,
  skip_unknown : Bool,
) -> Unit raise Fault {
  if parse == 0 {
    return
  }
  let dictionary = if custom == 0 { self.word(8) } else { custom }
  let separators = self.byte(dictionary)
  let start = if self.version == 3 { 1 } else { 2 }
  let length = if self.version == 5 {
    self.byte(buffer + 1)
  } else {
    let mut n = 0
    while self.byte(buffer + 1 + n) != 0 {
      n += 1
      if n >= self.byte(buffer) {
        raise Invalid("unterminated v3 input")
      }
    }
    n
  }
  let max = self.byte(parse)
  let mut count = 0
  let mut i = 0
  while i < length && count < max {
    let code = self.byte(buffer + start + i)
    if code == 32 {
      i += 1
      continue
    }
    let token_start = i
    let is_sep = fn(c) raise Fault {
      let mut found = false
      for j in 0..<separators {
        if self.byte(dictionary + 1 + j) == c {
          found = true
        }
      }
      found
    }
    if is_sep(code) {
      i += 1
    } else {
      while i < length {
        let c = self.byte(buffer + start + i)
        if c == 32 || is_sep(c) {
          break
        }
        i += 1
      }
    }
    let token : Array[Int32] = []
    for j in token_start..<i {
      token.push(self.byte(buffer + start + j))
    }
    let addr = self.lookup(token, dictionary)
    if addr != 0 || !skip_unknown {
      self.put_word(parse + 2 + 4 * count, addr)
      self.put_byte(parse + 4 + 4 * count, i - token_start)
      self.put_byte(parse + 5 + 4 * count, token_start + start)
    }
    // Unknown tokens still consume a parse slot when flag is set (Standard 15 tokenise).
    count += 1
  }
  self.put_byte(parse + 1, count)
}

///|
/// Supply one complete ASCII command when run returns "line".
/// Input is lowercased, clipped to the story's buffer, and tokenised.
pub fn Machine::send_line(self : Machine, line : String) -> Unit raise Fault {
  if self.waiting != 1 {
    raise Invalid("interpreter is not waiting for a line")
  }
  let data : Array[Int32] = []
  let max = self.byte(self.input_buffer) -
    (if self.version == 3 { 1 } else { 0 })
  for c in line.to_array() {
    let code = c.to_int()
    if code == 10 || code == 13 {
      break
    }
    if code < 32 || code > 126 {
      raise Invalid("line input currently supports printable ASCII")
    }
    if data.length() < max {
      data.push(if code >= 65 && code <= 90 { code + 32 } else { code })
    }
  }
  let start = if self.version == 3 { 1 } else { 2 }
  for i in 0..<data.length() {
    self.put_byte(self.input_buffer + start + i, data[i])
  }
  if self.version == 3 {
    self.put_byte(self.input_buffer + 1 + data.length(), 0)
  } else {
    self.put_byte(self.input_buffer + 1, data.length())
  }
  self.tokenise(self.input_buffer, self.parse_buffer, 0, false)
  if self.input_store >= 0 {
    self.assign(self.input_store, 13)
  }
  self.waiting = 0
}

///|
/// Supply a ZSCII character when run returns "char".
pub fn Machine::send_char(self : Machine, code : Int32) -> Unit raise Fault {
  if self.waiting != 2 || code < 0 || code > 255 {
    raise Invalid("invalid character input")
  }
  self.assign(self.input_store, code)
  self.waiting = 0
}
