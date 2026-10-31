// Controller regression tests. These mocks exercise host event ordering;
// interpreter execution is covered separately by verify-wasm.mjs and story tests.
import assert from 'node:assert/strict';

const ids = ['transcript','status','command','send','restore','savefile','stop','upper','demo','story','form','cancel'];
const elements = Object.fromEntries(ids.map(id => [id, {
  textContent: '', value: '', files: [], disabled: true, hidden: id === 'restore',
  scrollTop: 0, scrollHeight: 0, focus() {}
}]));
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const requests = [];
const state = { nextMode: 'line', starts: 0, restores: 0, cancels: 0, uploads: [], accept: true };
const machine = {
  load_size: size => { state.buffer = new Uint8Array(size); return 1; },
  load_byte: (i,b) => { state.buffer[i] = b; return 1; },
  start: () => { state.starts++; state.nextMode = 'line'; state.uploads.push([...state.buffer]); return 1; },
  step: () => state.nextMode,
  output: () => '', upper: () => '', error: () => 'rejected input',
  command: text => { if (!state.accept) return 0; state.nextMode = text === 'restore' ? 'restore' : 'line'; return 1; },
  key: () => 1,
  cancel_restore: () => { state.cancels++; state.nextMode = 'line'; return 1; },
  restore: () => { state.restores++; state.nextMode = 'line'; return 1; }
};
const realDocument = globalThis.document;
const realFetch = globalThis.fetch;
const realInstantiate = WebAssembly.instantiate;
globalThis.document = { getElementById: id => elements[id] };
globalThis.fetch = async url => {
  if (url === './browser.wasm') return { ok:true, arrayBuffer: async () => new ArrayBuffer(0) };
  const request = deferred(); requests.push(request); return request.promise;
};
WebAssembly.instantiate = async () => ({ instance: { exports: machine } });
const response = bytes => ({ ok:true, arrayBuffer: async () => Uint8Array.from(bytes).buffer });
const submit = text => { elements.command.value = text; elements.form.onsubmit({ preventDefault() {} }); };

try {
  await import('../web/player.mjs');
  assert.equal(elements.demo.disabled, false);
  const first = elements.demo.onclick();
  const second = elements.demo.onclick();
  requests[1].resolve(response([2])); await second;
  requests[0].resolve(response([1])); await first;
  assert.equal(state.starts, 1);
  assert.deepEqual(state.uploads, [[2]], 'a stale story request must not replace a newer game');

  submit('restore'); assert.equal(elements.restore.hidden, false);
  elements.stop.onclick();
  assert.equal(elements.restore.hidden, true);
  assert.equal(elements.command.disabled, true);
  elements.cancel.onclick();
  assert.equal(state.cancels, 0, 'a stale cancel action must not resume a stopped game');

  state.nextMode = 'line';
  const third = elements.demo.onclick(); requests[2].resolve(response([3])); await third;
  submit('restore');
  const pendingFile = deferred();
  elements.savefile.files = [{ size:1, arrayBuffer: () => pendingFile.promise }];
  const restoring = elements.savefile.onchange({ target:elements.savefile });
  elements.stop.onclick(); pendingFile.resolve(Uint8Array.from([9]).buffer); await restoring;
  assert.equal(state.restores, 0, 'a pending file read must not resurrect a stopped game');
  assert.equal(elements.restore.hidden, true);

  let readOversized = false;
  elements.story.files = [{ size:262145, arrayBuffer: () => { readOversized = true; throw Error('should not read'); } }];
  await elements.story.onchange({ target:elements.story });
  assert.equal(readOversized, false);
  assert.match(elements.status.textContent, /256 KiB/);

  const fourth = elements.demo.onclick(); requests[3].resolve(response([4])); await fourth;
  state.accept = false;
  const before = elements.transcript.textContent;
  submit('invalid');
  assert.equal(elements.command.value, 'invalid');
  assert.equal(elements.transcript.textContent, before);
  console.log('Browser controller: stale loads, stopped restores, file bounds and rejected input passed.');
} finally {
  globalThis.document = realDocument;
  globalThis.fetch = realFetch;
  WebAssembly.instantiate = realInstantiate;
}
