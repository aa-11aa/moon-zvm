import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const { instance } = await WebAssembly.instantiate(
  readFileSync('dist/browser.wasm'), {}, { builtins: ['js-string'], importedStringConstants: '_' }
);
const vm = instance.exports;
function upload(bytes) {assert.equal(vm.load_size(bytes.length),1);bytes.forEach((b,i)=>assert.equal(vm.load_byte(i,b),1));}
upload(readFileSync('examples/lantern.z5'));assert.equal(vm.start(),1,vm.error());
let log='';
function pump() {let mode;do{mode=vm.step();log+=vm.output();}while(mode==='budget');assert.notEqual(mode,'error',vm.error());return mode;}
assert.equal(pump(),'line');
for(const command of ['north','take','save']) {assert.equal(vm.command(command),1);pump();}
const length=vm.save_size();assert.ok(length>0,vm.error());
const saved=Uint8Array.from({length},(_,i)=>vm.save_byte(i));assert.equal(vm.saved(1),1);
assert.equal(pump(),'line');
assert.equal(vm.command('south'),1);assert.equal(pump(),'line');
assert.equal(vm.command('restore'),1);assert.equal(pump(),'restore');
upload(saved);assert.equal(vm.restore(),1,vm.error());assert.equal(pump(),'line');
for(const command of ['look','south','south','quit']) {assert.equal(vm.command(command),1);pump();}
assert.ok(log.includes('You have found the lost keeper\'s key!'));
assert.equal(log.match(/The watchtower overlooks/g)?.length,2);
assert.ok(log.endsWith('Goodbye.\n'));
console.log('Wasm GC exports: loading, input, save/restore and complete adventure passed.');
