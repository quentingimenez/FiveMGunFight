'use strict';
// gf_lobby NUI: error codes from the transport or the Lua callbacks must never
// reach the player as is. Run from the repository root: node --test tests/js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const NUI_JS = path.join(__dirname, '..', '..', 'server-data', 'resources', '[gunfight]',
  'gf_lobby', 'html', 'js', 'nui.js');

function loadNui() {
  const window = {};
  vm.runInNewContext(fs.readFileSync(NUI_JS, 'utf8'), { window }, { filename: NUI_JS });
  return window.NUI;
}

const FALLBACK = "Impossible d'afficher l'aperçu.";
const CODES = [
  'callback_unreachable', 'fetch_unavailable', 'nui_missing', 'internal_error',
  'invalid_payload', 'invalid_character', 'invalid_name',
];

test('every known code becomes a readable message', () => {
  const nui = loadNui();
  for (const code of CODES) {
    const text = nui.errorText(code, FALLBACK);
    assert.equal(typeof text, 'string', code);
    assert.ok(text.length > 0, code);
    assert.ok(!text.includes(code), `${code} leaks into "${text}"`);
    assert.notEqual(text, FALLBACK, `${code} has its own message`);
  }
});

test('an unknown code falls back to the caller message', () => {
  const nui = loadNui();
  assert.equal(nui.errorText('some_new_code', FALLBACK), FALLBACK);
  assert.equal(nui.errorText('timeout', FALLBACK), FALLBACK);
});

test('missing or non-text errors fall back to the caller message', () => {
  const nui = loadNui();
  for (const value of [undefined, null, '', 42, {}, true]) {
    assert.equal(nui.errorText(value, FALLBACK), FALLBACK, String(value));
  }
});

test('a sentence written for the player is kept', () => {
  const nui = loadNui();
  for (const sentence of [
    'Tu as déjà un personnage.',
    'Patiente avant de reessayer',
    'serveur plein, reessaie plus tard',
  ]) {
    assert.equal(nui.errorText(sentence, FALLBACK), sentence);
  }
});
