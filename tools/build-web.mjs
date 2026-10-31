import { spawnSync } from 'node:child_process';
import { mkdirSync, copyFileSync } from 'node:fs';
const built = spawnSync('moon', ['build', 'browser', '--target', 'wasm-gc', '--release'], { stdio: 'inherit' });
if (built.status !== 0) process.exit(built.status ?? 1);
mkdirSync('dist', { recursive: true });
copyFileSync('_build/wasm-gc/release/build/browser/browser.wasm', 'dist/browser.wasm');
copyFileSync('web/index.html', 'dist/index.html');
copyFileSync('examples/lantern.z5', 'dist/lantern.z5');
console.log('Ready: serve dist/ with a local HTTP server.');
