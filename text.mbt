///|
fn Machine::emit(self : Machine, code : Int32) -> Unit raise Fault {
  if code == 0 {
    return
  }
  if !self.streams.is_empty() {
    let table = self.streams[self.streams.length() - 1]
    let n = self.word(table)
    self.put_byte(table + 2 + n, code)
    self.put_word(table, n + 1)
  } else if self.screen {
    if code == 13 {
      self.display_char(10)
    } else if code >= 32 && code <= 126 {
      self.display_char(code)
    } else if code >= 155 && code <= 251 {
      let ext = if self.version == 5 { self.word(54) } else { 0 }
      let unicode = if ext != 0 && self.word(ext) >= 3 {
        self.word(ext + 6)
      } else {
        0
      }
      if unicode != 0 && code - 155 < self.byte(unicode) {
        let c = self.word(unicode + 1 + 2 * (code - 155))
        if c >= 0xd800 && c <= 0xdfff {
          raise Invalid("surrogate Unicode character")
        }
        self.display_char(c)
      } else {
        let standard = "äöüÄÖÜß»«ëïÿËÏáéíóúýÁÉÍÓÚÝàèìòùÀÈÌÒÙâêîôûÂÊÎÔÛåÅøØãñõÃÑÕæÆçÇþðÞÐ£œŒ¡¿"
        if code - 155 < standard.length() {
          self.display_char(standard[code - 155].to_int())
        } else {
          raise Invalid("undefined ZSCII character")
        }
      }
    } else {
      raise Invalid("unsupported ZSCII output code \{code}")
    }
  }
}

///|
fn Machine::print_text(
  self : Machine,
  addr : Int32,
  depth~ : Int32 = 0,
) -> Int32 raise Fault {
  if depth > 16 {
    raise Invalid("recursive abbreviation")
  }
  let zchars : Array[Int32] = []
  let mut p = addr
  while true {
    let w = self.word(p)
    p += 2
    zchars.push((w >> 10) & 31)
    zchars.push((w >> 5) & 31)
    zchars.push(w & 31)
    if (w & 32768) != 0 {
      break
    }
  }
  let mut alphabet = 0
  let mut i = 0
  while i < zchars.length() {
    let z = zchars[i]
    i += 1
    if z == 0 {
      self.emit(32)
      alphabet = 0
    } else if z >= 1 && z <= 3 {
      if depth != 0 {
        raise Invalid("abbreviation nested inside abbreviation")
      }
      if i >= zchars.length() {
        raise Invalid("truncated abbreviation")
      }
      let index = 32 * (z - 1) + zchars[i]
      i += 1
      let _ = self.print_text(
        self.word(self.abbreviations + 2 * index) * 2,
        depth=depth + 1,
      )
      alphabet = 0
    } else if z == 4 {
      alphabet = 1
    } else if z == 5 {
      alphabet = 2
    } else if alphabet == 2 && z == 6 {
      if i + 1 >= zchars.length() {
        raise Invalid("truncated ZSCII escape")
      }
      self.emit(zchars[i] * 32 + zchars[i + 1])
      i += 2
      alphabet = 0
    } else {
      let custom = if self.version == 5 { self.word(52) } else { 0 }
      let code = if custom != 0 {
        self.byte(custom + alphabet * 26 + z - 6)
      } else if alphabet == 0 {
        97 + z - 6
      } else if alphabet == 1 {
        65 + z - 6
      } else if z == 7 {
        13
      } else {
        let punctuation = "0123456789.,!?_#'\"/\\-:()"
        punctuation[z - 8].to_int()
      }
      self.emit(code)
      alphabet = 0
    }
  }
  p
}
