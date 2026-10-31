///|
let default_extra_characters : String = "äöüÄÖÜß»«ëïÿËÏáéíóúýÁÉÍÓÚÝàèìòùÀÈÌÒÙâêîôûÂÊÎÔÛåÅøØãñõÃÑÕæÆçÇþðÞÐ£œŒ¡¿"

///|
fn Machine::extra_character_table(self : Machine) -> (Int32, Int32) raise Fault {
  let extension = if self.version == 5 { self.word(54) } else { 0 }
  let table = if extension != 0 && self.word(extension) >= 3 {
    self.word(extension + 6)
  } else {
    0
  }
  let count = if table == 0 {
    default_extra_characters.length()
  } else {
    self.byte(table)
  }
  if count > 97 {
    raise Invalid("Unicode translation table exceeds 97 characters")
  }
  (table, count)
}

///|
fn Machine::extra_character(
  self : Machine,
  table : Int32,
  index : Int32,
) -> Int32 raise Fault {
  let code = if table == 0 {
    default_extra_characters[index].to_int()
  } else {
    self.word(table + 1 + 2 * index)
  }
  if code >= 0xd800 && code <= 0xdfff {
    raise Invalid("surrogate Unicode character")
  }
  code
}

///|
fn Machine::unicode_zscii(self : Machine, code : Int32) -> Int32 raise Fault {
  if code >= 32 && code <= 126 {
    return code
  }
  if code == 10 || code == 13 {
    return 13
  }
  if code == 0 {
    return 0
  }
  let (table, count) = self.extra_character_table()
  for i in 0..<count {
    if self.extra_character(table, i) == code {
      return i + 155
    }
  }
  63
}

///|
fn Machine::emit_unicode(self : Machine, code : Int32) -> Unit raise Fault {
  if code >= 0xd800 && code <= 0xdfff {
    raise Invalid("surrogate Unicode character")
  }
  if !self.streams.is_empty() {
    self.emit(self.unicode_zscii(code))
  } else if self.screen {
    self.display_char(code)
  }
}

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
      let (table, count) = self.extra_character_table()
      if code - 155 >= count {
        raise Invalid("undefined ZSCII character")
      }
      self.display_char(self.extra_character(table, code - 155))
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
