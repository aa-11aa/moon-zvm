///|
extern "js" fn read_story(path : String) -> Bytes =
  #| (path) => { try { return new Uint8Array(process.getBuiltinModule('node:fs').readFileSync(path)); } catch(e) { console.error('Cannot read file: '+e.message); return new Uint8Array(); } }

///|
extern "js" fn write_output(text : String) -> Unit =
  #| (text) => { process.stdout.write(text); }

///|
extern "js" fn write_save(path : String, data : Bytes) -> Bool =
  #| (path, data) => { try { process.getBuiltinModule('node:fs').writeFileSync(path, data); return true; } catch(e) { console.error('Cannot save file: '+e.message); return false; } }

///|
extern "js" fn exit_error(message : String) -> Unit =
  #| (message) => { console.error(message); process.exitCode = 1; }

///|
extern "js" fn read_line() -> String =
  #| () => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   const bytes = []; const b = Buffer.alloc(1); let n;
  #|   while ((n = fs.readSync(0, b, 0, 1, null))) { if (b[0] === 10) break; if (b[0] !== 13) bytes.push(b[0]); }
  #|   if (!n && !bytes.length) throw new Error('End of input');
  #|   return Buffer.from(bytes).toString('utf8');
  #| }

///|
extern "js" fn random_seed() -> Int32 =
  #| () => process.getBuiltinModule('node:crypto').randomInt(0, 65536)

///|
fn main {
  let args = @env.args()
  let tracing = args.length() == 5 && args[2] == "--trace"
  let mut trace_left = if tracing { decimal_arg(args[3]) } else { 0 }
  if tracing && (trace_left < 1 || trace_left > 10000) {
    exit_error("Trace count must be a decimal integer in 1..10000")
    return
  }
  if args.length() == 6 && args[2] == "--disassemble" {
    try {
      let story = read_story(args[5])
      let mut address = decimal_arg(args[3])
      let count = decimal_arg(args[4])
      if address < 64 || count < 1 || count > 10000 {
        raise @zvm.Invalid(
          "Expected decimal address >=64 and instruction count 1..10000",
        )
      }
      for _ in 0..<count {
        let instruction = @zvm.inspect_instruction(story, address)
        println(instruction.format())
        address = instruction.next_address
      }
    } catch {
      @zvm.Invalid(message) => exit_error(message)
    }
    return
  }
  if args.length() == 4 && args[2] == "--info" {
    try {
      let info = @zvm.inspect_story(read_story(args[3]))
      println("Version: \{info.version}")
      println("Release: \{info.release}")
      println("Serial: \{info.serial}")
      println("Initial PC: \{info.initial_pc}")
      println("Dynamic memory: 0..\{info.static_memory}")
      println("High memory: \{info.high_memory}")
      println(
        "File bytes: \{info.actual_length} (declared \{info.declared_length})",
      )
      let checksum = match info.checksum_valid {
        Some(true) => "verified"
        Some(false) => "mismatch"
        None => "not provided"
      }
      println("Checksum: \{checksum}")
    } catch {
      @zvm.Invalid(message) => exit_error(message)
    }
    return
  }
  if args.length() != 3 && !tracing {
    exit_error(
      "Usage: moon run cmd/main --target js -- [--info | --trace COUNT | --disassemble ADDRESS COUNT] story.z3|story.z5",
    )
    return
  }
  try {
    let machine = @zvm.Machine::new(
      read_story(args[if tracing { 4 } else { 2 }]),
      seed_source=random_seed,
    )
    let mut slices = 0
    while !machine.is_halted() {
      let budget = if trace_left > 0 { 1 } else { 100000 }
      if trace_left > 0 {
        write_trace(machine.peek_instruction().format())
        trace_left -= 1
        if trace_left == 0 {
          write_trace("Trace limit reached; continuing without trace.")
        }
      }
      let status = machine.run(budget~) catch {
        @zvm.Invalid(message) => {
          write_output(machine.take_output())
          raise @zvm.Invalid(message)
        }
      }
      write_output(machine.take_output())
      if status == "line" {
        machine.send_line(read_line())
        slices = 0
      } else if status == "char" {
        let line = read_line()
        machine.send_char(if line.is_empty() { 13 } else { line[0].to_int() })
        slices = 0
      } else if status == "save" {
        write_output("Save file (blank cancels): ")
        let path = read_line()
        if path.is_empty() {
          machine.finish_save(false)
        } else {
          machine.finish_save(write_save(path, machine.save_data()))
        }
      } else if status == "restore" {
        write_output("Restore file (blank cancels): ")
        let path = read_line()
        if path.is_empty() {
          machine.cancel_restore()
        } else {
          machine.restore_data(read_story(path)) catch {
            @zvm.Invalid(message) => {
              write_output("Restore rejected: \{message}\n")
              machine.cancel_restore()
            }
          }
        }
      } else if status == "budget" {
        slices += budget
        if slices > 100000000 {
          fail("instruction limit exceeded")
        }
      }
    }
  } catch {
    @zvm.Invalid(message) => exit_error("Interpreter error: \{message}")
    error => exit_error("Interpreter error: \{error}")
  }
}

///|
extern "js" fn decimal_arg(value : String) -> Int32 =
  #| value => /^[0-9]+$/.test(value) && Number(value) <= 2147483647 ? Number(value) : -1

///|
extern "js" fn write_trace(value : String) -> Unit =
  #| value => process.stderr.write(value + '\n')
