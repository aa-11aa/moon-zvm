const $ = id => document.getElementById(id);
let vm, mode = '', ticket = 0;

function say(text) {
  $('transcript').textContent += text;
  $('transcript').scrollTop = $('transcript').scrollHeight;
}

function status(text) { $('status').textContent = text; }
function enableInput(enabled) { $('command').disabled = $('send').disabled = !enabled; }
function closeRestore() {
  $('restore').hidden = true;
  $('savefile').value = '';
}

function upload(bytes) {
  if (!vm.load_size(bytes.length)) throw Error(vm.error());
  for (let i = 0; i < bytes.length; i++) {
    if (!vm.load_byte(i, bytes[i])) throw Error(vm.error());
  }
}

function halt(message) {
  ticket++;
  mode = '';
  enableInput(false);
  closeRestore();
  $('stop').disabled = true;
  status(message);
}

function beginLoad() {
  ticket++;
  mode = '';
  enableInput(false);
  closeRestore();
  $('stop').disabled = false;
  status('Loading story…');
  return ticket;
}

function pump(id) {
  if (id !== ticket) return;
  mode = vm.step();
  say(vm.output());
  $('upper').textContent = vm.upper();
  enableInput(['line', 'char'].includes(mode));
  if (mode === 'budget') {
    status('Running…');
    setTimeout(() => pump(id), 0);
  } else if (mode === 'line' || mode === 'char') {
    status(mode === 'line' ? 'Your turn.' : 'Waiting for a character.');
    $('command').focus();
  } else if (mode === 'halted') {
    halt('Story finished. Load a story to start again.');
  } else if (mode === 'error') {
    halt('Interpreter error: ' + vm.error());
  } else if (mode === 'save') {
    const size = vm.save_size();
    if (size < 0) { vm.saved(false); halt(vm.error()); return; }
    const bytes = Uint8Array.from({ length: size }, (_, i) => vm.save_byte(i));
    const url = URL.createObjectURL(new Blob([bytes], { type: 'application/octet-stream' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'moon-zvm.sav';
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
    if (!vm.saved(true)) { halt(vm.error()); return; }
    status('Save downloaded.');
    setTimeout(() => pump(id), 0);
  } else if (mode === 'restore') {
    $('restore').hidden = false;
    status('Choose a Quetzal save, or cancel.');
  }
}

function load(bytes, id) {
  if (id !== ticket) return;
  upload(bytes);
  if (!vm.start()) throw Error(vm.error());
  $('transcript').textContent = '';
  $('upper').textContent = '';
  pump(id);
}

try {
  const response = await fetch('./browser.wasm');
  if (!response.ok) throw Error('Cannot load browser.wasm');
  const imports = { host: { random_seed: () => crypto.getRandomValues(new Uint16Array(1))[0] } };
  const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), imports, {
    builtins: ['js-string'], importedStringConstants: '_'
  });
  vm = instance.exports;
  $('demo').disabled = $('story').disabled = false;
  status('Ready. Choose an adventure.');
} catch (error) { status('Could not start: ' + error.message); }

$('demo').onclick = async () => {
  const id = beginLoad();
  try {
    const response = await fetch('./lantern.z5');
    if (!response.ok) throw Error('Demo unavailable');
    load(new Uint8Array(await response.arrayBuffer()), id);
  } catch (error) { if (id === ticket) halt(error.message); }
};

$('story').onchange = async event => {
  const file = event.target.files[0];
  if (!file) return;
  const id = beginLoad();
  try {
    if (file.size > 262144) throw Error('Raw v3/v5 stories must be at most 256 KiB.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (id !== ticket) return;
    event.target.value = '';
    load(bytes, id);
  } catch (error) {
    if (id === ticket) { event.target.value = ''; halt(error.message); }
  }
};

$('form').onsubmit = event => {
  event.preventDefault();
  if (!['line', 'char'].includes(mode)) return;
  const text = $('command').value;
  const ok = mode === 'line' ? vm.command(text) : vm.key(text.length ? text.charCodeAt(0) : 13);
  if (!ok) { status(vm.error()); return; }
  $('command').value = '';
  say(text + '\n');
  pump(ticket);
};

$('stop').onclick = () => halt('Stopped. Reload a story to restart.');
$('cancel').onclick = () => {
  if (mode !== 'restore') return;
  if (!vm.cancel_restore()) { halt(vm.error()); return; }
  closeRestore();
  pump(ticket);
};

$('savefile').onchange = async event => {
  const file = event.target.files[0];
  if (!file || mode !== 'restore') return;
  const id = ticket;
  try {
    if (file.size > 4194304) throw Error('Save files must be at most 4 MiB.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (id !== ticket || mode !== 'restore') return;
    upload(bytes);
    if (!vm.restore()) throw Error(vm.error());
    closeRestore();
    pump(id);
  } catch (error) {
    if (id === ticket && mode === 'restore') {
      event.target.value = '';
      status('Restore rejected: ' + error.message);
    }
  }
};
