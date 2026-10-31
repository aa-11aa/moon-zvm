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
fn main {
  let args = @env.args()
  if args.length() != 3 {
    exit_error("Usage: moon run cmd/main --target js -- story.z3|story.z5")
    return
  }
  try {
    let machine = @zvm.Machine::new(read_story(args[2]))
    let mut slices = 0
    while !machine.is_halted() {
      let status = machine.run() catch {
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
        slices += 1
        if slices > 1000 {
          fail("instruction limit exceeded")
        }
      }
    }
  } catch {
    @zvm.Invalid(message) => exit_error("Interpreter error: \{message}")
    error => exit_error("Interpreter error: \{error}")
  }
}
