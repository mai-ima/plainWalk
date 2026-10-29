import test from 'node:test';import assert from 'node:assert/strict';import {parseCube,applyEffect} from '../dist/effects.js';
const cube='LUT_3D_SIZE 2\n'+Array.from({length:8},(_,n)=>`${n&1} ${(n>>1)&1} ${(n>>2)&1}`).join('\n');
test('identity cube keeps all channels and alpha',()=>{const image={data:new Uint8ClampedArray([17,123,241,160,0,255,128,255])};const expected=[...image.data];applyEffect(image,'custom',parseCube(cube));assert.deepEqual([...image.data],expected)});
test('cube validates number of colors and domain',()=>{assert.throws(()=>parseCube('LUT_3D_SIZE 3\n0 0 0'));assert.throws(()=>parseCube('LUT_3D_SIZE 65'));assert.throws(()=>parseCube('DOMAIN_MIN 1 0 0\n'+cube))});
test('monochrome preserves transparency and produces equal channels',()=>{const image={data:new Uint8ClampedArray([200,30,80,123])};applyEffect(image,'grayscale(1)');assert.equal(image.data[0],image.data[1]);assert.equal(image.data[1],image.data[2]);assert.equal(image.data[3],123)});
