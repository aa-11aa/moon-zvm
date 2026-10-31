///|
fn Machine::object_addr(self : Machine, obj : Int32) -> Int32 raise Fault {
  let limit = if self.version == 3 { 255 } else { 65535 }
  if obj <= 0 || obj > limit {
    raise Invalid("invalid object number")
  }
  let addr = self.objects +
    (if self.version == 3 { 62 + (obj - 1) * 9 } else { 126 + (obj - 1) * 14 })
  if addr > self.static_base - (if self.version == 3 { 9 } else { 14 }) {
    raise Invalid("object outside dynamic memory")
  }
  addr
}

///|
fn Machine::relation(
  self : Machine,
  obj : Int32,
  which : Int32,
) -> Int32 raise Fault {
  if obj == 0 {
    return 0
  }
  let p = self.object_addr(obj)
  if self.version == 3 {
    self.byte(p + 4 + which)
  } else {
    self.word(p + 6 + which * 2)
  }
}

///|
fn Machine::set_relation(
  self : Machine,
  obj : Int32,
  which : Int32,
  value : Int32,
) -> Unit raise Fault {
  let p = self.object_addr(obj)
  if self.version == 3 {
    self.put_byte(p + 4 + which, value)
  } else {
    self.put_word(p + 6 + which * 2, value)
  }
}

///|
fn Machine::remove_object(self : Machine, obj : Int32) -> Unit raise Fault {
  let parent = self.relation(obj, 0)
  if parent == 0 {
    return
  }
  let next = self.relation(obj, 1)
  let first = self.relation(parent, 2)
  if first == obj {
    self.set_relation(parent, 2, next)
  } else {
    let mut cursor = first
    let mut limit = 65536
    while cursor != 0 && self.relation(cursor, 1) != obj {
      cursor = self.relation(cursor, 1)
      limit -= 1
      if limit == 0 {
        raise Invalid("cyclic sibling chain")
      }
    }
    if cursor == 0 {
      raise Invalid("object absent from parent")
    }
    self.set_relation(cursor, 1, next)
  }
  self.set_relation(obj, 0, 0)
  self.set_relation(obj, 1, 0)
}

///|
fn Machine::insert_object(
  self : Machine,
  obj : Int32,
  parent : Int32,
) -> Unit raise Fault {
  let _ = self.object_addr(parent)
  let mut p = parent
  let mut limit = 65536
  while p != 0 {
    if p == obj {
      raise Invalid("cyclic object insertion")
    }
    p = self.relation(p, 0)
    limit -= 1
    if limit == 0 {
      raise Invalid("cyclic object tree")
    }
  }
  self.remove_object(obj)
  let child = self.relation(parent, 2)
  self.set_relation(obj, 0, parent)
  self.set_relation(obj, 1, child)
  self.set_relation(parent, 2, obj)
}

///|
fn Machine::attribute(
  self : Machine,
  obj : Int32,
  attr : Int32,
  action : Int32,
) -> Bool raise Fault {
  let max = if self.version == 3 { 32 } else { 48 }
  if attr < 0 || attr >= max {
    raise Invalid("invalid attribute number")
  }
  let addr = self.object_addr(obj) + attr / 8
  let mask = 128 >> (attr % 8)
  let b = self.byte(addr)
  if action == 1 {
    self.put_byte(addr, b | mask)
  }
  if action == 2 {
    self.put_byte(addr, b & (255 ^ mask))
  }
  (b & mask) != 0
}

///|
fn Machine::property_table(self : Machine, obj : Int32) -> Int32 raise Fault {
  self.word(self.object_addr(obj) + (if self.version == 3 { 7 } else { 12 }))
}

///|
fn Machine::property_info(
  self : Machine,
  addr : Int32,
) -> (Int32, Int32, Int32) raise Fault {
  let b = self.byte(addr)
  if b == 0 {
    return (0, addr + 1, 0)
  }
  if self.version == 3 {
    (b & 31, addr + 1, (b >> 5) + 1)
  } else if (b & 128) == 0 {
    (b & 63, addr + 1, if (b & 64) == 0 { 1 } else { 2 })
  } else {
    let size = self.byte(addr + 1) & 63
    (b & 63, addr + 2, if size == 0 { 64 } else { size })
  }
}

///|
fn Machine::find_property(
  self : Machine,
  obj : Int32,
  prop : Int32,
) -> (Int32, Int32) raise Fault {
  let table = self.property_table(obj)
  let mut addr = table + 1 + 2 * self.byte(table)
  let mut previous = if self.version == 3 { 32 } else { 64 }
  while true {
    let (number, data, size) = self.property_info(addr)
    if number == 0 {
      return (0, 0)
    }
    if number >= previous {
      raise Invalid("properties are not in descending order")
    }
    if number == prop {
      return (data, size)
    }
    previous = number
    addr = data + size
  } nobreak {
    (0, 0)
  }
}

///|
fn Machine::get_property(
  self : Machine,
  obj : Int32,
  prop : Int32,
) -> Int32 raise Fault {
  let max = if self.version == 3 { 31 } else { 63 }
  if prop < 1 || prop > max {
    raise Invalid("invalid property number")
  }
  let (addr, size) = self.find_property(obj, prop)
  if addr == 0 {
    self.word(self.objects + 2 * (prop - 1))
  } else if size == 1 {
    self.byte(addr)
  } else {
    self.word(addr)
  }
}

///|
fn Machine::next_property(
  self : Machine,
  obj : Int32,
  prop : Int32,
) -> Int32 raise Fault {
  let table = self.property_table(obj)
  let addr = if prop == 0 {
    table + 1 + 2 * self.byte(table)
  } else {
    let (data, size) = self.find_property(obj, prop)
    if data == 0 {
      raise Invalid("property not found")
    }
    data + size
  }
  let (number, _, _) = self.property_info(addr)
  number
}

///|
fn Machine::property_length(self : Machine, data : Int32) -> Int32 raise Fault {
  if data == 0 {
    return 0
  }
  let b = self.byte(data - 1)
  if self.version == 3 {
    (b >> 5) + 1
  } else if (b & 128) != 0 {
    let n = b & 63
    if n == 0 {
      64
    } else {
      n
    }
  } else if (b & 64) != 0 {
    2
  } else {
    1
  }
}
