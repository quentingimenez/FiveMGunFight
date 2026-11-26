'use strict';
// Rail du menu pause : déplacement, bouclage et entrées invalides.
// Lancer depuis la racine : node --test tests/js/menu_nav.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const NAV_JS = path.join(__dirname, '..', '..', 'server-data', 'resources', '[gunfight]',
  'gf_menu', 'html', 'js', 'nav.js');
const nav = require(NAV_JS);

test('expose nextIndex', () => {
  assert.equal(typeof nav.nextIndex, 'function');
  assert.equal(nav.nextIndex(3, 1, 1), 2);
});

test('moves one step down and up', () => {
  assert.equal(nav.nextIndex(12, 0, 1), 1);
  assert.equal(nav.nextIndex(12, 5, 1), 6);
  assert.equal(nav.nextIndex(12, 5, -1), 4);
  assert.equal(nav.nextIndex(12, 1, -1), 0);
});

test('wraps at the bottom and at the top', () => {
  assert.equal(nav.nextIndex(12, 11, 1), 0);
  assert.equal(nav.nextIndex(12, 0, -1), 11);
  assert.equal(nav.nextIndex(1, 0, 1), 0);
  assert.equal(nav.nextIndex(1, 0, -1), 0);
});

test('handles empty or invalid counts', () => {
  for (const count of [0, -1, 2.5, NaN, undefined, null, '12']) {
    assert.equal(nav.nextIndex(count, 0, 1), -1, String(count));
  }
});

test('recovers from an invalid current index', () => {
  for (const current of [-1, 12, 99, 1.5, NaN, undefined, null, '3']) {
    assert.equal(nav.nextIndex(12, current, 1), 0, `down from ${String(current)}`);
    assert.equal(nav.nextIndex(12, current, -1), 11, `up from ${String(current)}`);
  }
});

test('invalid delta keeps a valid current index', () => {
  for (const delta of [NaN, undefined, null, '1', 1.5]) {
    assert.equal(nav.nextIndex(12, 7, delta), 7, String(delta));
  }
  assert.equal(nav.nextIndex(12, -1, NaN), -1);
});

test('zero and large deltas wrap inside the range', () => {
  assert.equal(nav.nextIndex(12, 4, 0), 4);
  assert.equal(nav.nextIndex(12, 4, 12), 4);
  assert.equal(nav.nextIndex(12, 4, -13), 3);
});
