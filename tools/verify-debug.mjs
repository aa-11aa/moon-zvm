// Exercise the real Node CLI, including separate transcript/diagnostic channels.
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
const root = fileURLToPath(new URL('../', import.meta.url));
const cli = resolve(root, '_build/js/debug/build/cmd/main/main.js');
function run(args, input = '') {
  return spawnSync(process.execPath, [cli, ...args], {
    cwd: root, input, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024
  });
}
for (const version of [3, 5]) {
  const story = `examples/lantern.z${version}`;
  const normal = run([story], 'look\nquit\n');
  const traced = run(['--trace', '10000', story], 'look\nquit\n');
  assert.equal(normal.status, 0, normal.stderr);
  assert.equal(traced.status, 0, traced.stderr);
  assert.equal(traced.stdout, normal.stdout);
  assert.match(traced.stderr, /call/);
  assert.match(traced.stderr, /quit/);
  const limited = run(['--trace', '2', story], 'quit\n');
  assert.equal(limited.status, 0, limited.stderr);
  assert.equal(limited.stderr.trim().split('\n').length, 3);
  assert.match(limited.stderr, /Trace limit reached/);
}
for (const count of ['0', '-1', '10001', 'abc', '4294967296']) {
  const result = run(['--trace', count, 'examples/lantern.z5']);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
}
const listing = run(['--disassemble', '1621', '2', 'examples/lantern.z5']);
assert.equal(listing.status, 0, listing.stderr);
assert.match(listing.stdout, /1621: call_vs/);
assert.match(listing.stdout, /1626: quit/);
console.log('CLI inspection and bounded trace: v3/v5 transcripts unchanged.');
const scratch = mkdtempSync(resolve(tmpdir(), 'moon-zvm-blorb-'));
try {
  for (const version of [3, 5]) {
    const path = `examples/lantern.z${version}`;
    const story = readFileSync(resolve(root, path));
    const data = Buffer.alloc(44 + story.length + (story.length & 1));
    data.write('FORM', 0); data.writeUInt32BE(data.length - 8, 4);
    data.write('IFRSRIdx', 8); data.writeUInt32BE(16, 16);
    data.writeUInt32BE(1, 20); data.write('Exec', 24);
    data.writeUInt32BE(36, 32); data.write('ZCOD', 36);
    data.writeUInt32BE(story.length, 40); story.copy(data, 44);
    const wrapped = resolve(scratch, `lantern-${version}.zblorb`);
    writeFileSync(wrapped, data);
    const actual = run([wrapped], 'look\nquit\n');
    const expected = run([path], 'look\nquit\n');
    assert.equal(actual.status, 0, actual.stderr);
    assert.equal(actual.stdout, expected.stdout);
    assert.equal(run(['--info', wrapped]).stdout, run(['--info', path]).stdout);
  }
} finally { rmSync(scratch, { recursive: true, force: true }); }
console.log('CLI Blorb extraction: v3/v5 transcripts and metadata match raw stories.');
