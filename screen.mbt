///|
fn Machine::display_char(self : Machine, code : Int32) -> Unit raise Fault {
  if self.output_count >= 1048576 {
    raise Invalid("output limit exceeded; drain output between runs")
  }
  self.output_count += 1
  let w = self.window
  if w == 0 {
    self.output.write_char(code.unsafe_to_char())
  }
  if code == 10 {
    self.rows[w] += 1
    self.columns[w] = 1
  } else {
    if w == 1 && self.rows[1] <= self.split && self.columns[1] <= 80 {
      self.upper[(self.rows[1] - 1) * 80 + self.columns[1] - 1] = code
    }
    self.columns[w] += 1
    if w == 0 && self.columns[w] > 80 {
      self.columns[w] = 1
      self.rows[w] += 1
    }
  }
}

///|
/// Current upper window as fixed-width text. Lower-window output uses take_output().
pub fn Machine::upper_window(self : Machine) -> String {
  let out = StringBuilder()
  for row in 0..<self.split {
    if row != 0 {
      out.write_char('\n')
    }
    for col in 0..<80 {
      out.write_char(self.upper[row * 80 + col].unsafe_to_char())
    }
  }
  out.to_string()
}

///|
fn Machine::split_window(self : Machine, height : Int32) -> Unit raise Fault {
  if height < 0 || height > 25 {
    raise Invalid("invalid split height")
  }
  self.split = height
  if self.version == 3 {
    self.upper.fill(32)
  }
  if self.rows[1] > height {
    self.rows[1] = 1
    self.columns[1] = 1
  }
  if height == 0 {
    self.window = 0
  }
}

///|
fn Machine::select_window(self : Machine, window : Int32) -> Unit raise Fault {
  if window != 0 && window != 1 {
    raise Invalid("invalid window")
  }
  self.window = window
  if window == 1 {
    self.rows[1] = 1
    self.columns[1] = 1
  }
}

///|
fn Machine::erase_window(self : Machine, window : Int32) -> Unit raise Fault {
  match signed(window) {
    -1 => {
      self.split = 0
      self.window = 0
      self.upper.fill(32)
      self.rows[0] = 1
      self.columns[0] = 1
    }
    -2 => {
      self.upper.fill(32)
      self.rows[0] = 1
      self.columns[0] = 1
    }
    0 => {
      self.rows[0] = 1
      self.columns[0] = 1
    }
    1 => {
      self.upper.fill(32)
      self.rows[1] = 1
      self.columns[1] = 1
    }
    _ => raise Invalid("invalid erase_window operand")
  }
}
