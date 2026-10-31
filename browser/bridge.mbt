///|
priv struct Host {
  mut bytes : Array[Byte]
  mut machine : @zvm.Machine?
  mut message : String
  mut saved_bytes : Bytes
}

///|
let host : Host = { bytes: [], machine: None, message: "", saved_bytes: b"", }

///|
pub fn load_size(size : Int32) -> Bool {
  if size < 0 || size > 4194304 {
    host.message = "file too large"
    return false
  }
  host.bytes = Array::make(size, b'\x00')
  true
}

///|
pub fn load_byte(index : Int32, value : Int32) -> Bool {
  if index < 0 || index >= host.bytes.length() || value < 0 || value > 255 {
    host.message = "invalid byte upload"
    return false
  }
  host.bytes[index] = value.to_byte()
  true
}

///|
extern "wasm" fn random_seed() -> Int32 = "host" "random_seed"

///|
pub fn start() -> Bool {
  try {
    let machine = @zvm.Machine::new(
      Bytes::from_array(host.bytes),
      seed_source=random_seed,
    )
    host.machine = Some(machine)
    host.message = ""
    true
  } catch {
    @zvm.Invalid(message) => {
      host.message = message
      host.machine = None
      false
    }
  }
}

///|
pub fn step() -> String {
  match host.machine {
    Some(machine) =>
      machine.run(budget=20000) catch {
        @zvm.Invalid(message) => {
          host.message = message
          "error"
        }
      }
    None => {
      host.message = "no story loaded"
      "error"
    }
  }
}

///|
pub fn output() -> String {
  match host.machine {
    Some(m) => m.take_output()
    None => ""
  }
}

///|
pub fn upper() -> String {
  match host.machine {
    Some(m) => m.upper_window()
    None => ""
  }
}

///|
pub fn error() -> String {
  host.message
}

///|
pub fn command(text : String) -> Bool {
  match host.machine {
    Some(m) =>
      try {
        m.send_line(text)
        true
      } catch {
        @zvm.Invalid(message) => {
          host.message = message
          false
        }
      }
    None => false
  }
}

///|
pub fn key(code : Int32) -> Bool {
  match host.machine {
    Some(m) =>
      try {
        m.send_char(code)
        true
      } catch {
        @zvm.Invalid(message) => {
          host.message = message
          false
        }
      }
    None => false
  }
}

///|
pub fn save_size() -> Int32 {
  match host.machine {
    Some(m) =>
      try {
        host.saved_bytes = m.save_data()
        host.saved_bytes.length()
      } catch {
        @zvm.Invalid(message) => {
          host.message = message
          -1
        }
      }
    None => -1
  }
}

///|
pub fn save_byte(index : Int32) -> Int32 {
  if index < 0 || index >= host.saved_bytes.length() {
    return -1
  }
  host.saved_bytes[index].to_int()
}

///|
pub fn saved(success : Bool) -> Bool {
  match host.machine {
    Some(m) =>
      try {
        m.finish_save(success)
        true
      } catch {
        @zvm.Invalid(message) => {
          host.message = message
          false
        }
      }
    None => false
  }
}

///|
pub fn restore() -> Bool {
  match host.machine {
    Some(m) =>
      try {
        m.restore_data(Bytes::from_array(host.bytes))
        true
      } catch {
        @zvm.Invalid(message) => {
          host.message = message
          false
        }
      }
    None => false
  }
}

///|
pub fn cancel_restore() -> Bool {
  match host.machine {
    Some(m) =>
      try {
        m.cancel_restore()
        true
      } catch {
        @zvm.Invalid(message) => {
          host.message = message
          false
        }
      }
    None => false
  }
}
