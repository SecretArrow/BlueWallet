import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Embed drift + module-graph guards for Fase C1.
 *
 * The embedded copies are vendored (Android assets + Flutter assets) so the
 * local web server can serve ES modules. They MUST stay byte-identical to
 * sdk/src, and every relative import must resolve on disk — a drifted or
 * broken copy only fails at runtime inside the wallet browser.
 */
const SDK = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = resolve(SDK, '..');
const EMBEDS = [
  join(REPO, 'android-native/app/src/main/assets/webcli'),
  join(REPO, 'flutter/assets/webcli'),
];
const MODULES = [
  'adapter.mjs',
  'errors.mjs',
  'index.mjs',
  'protocol.mjs',
  'transports.mjs',
  'units.mjs',
];

describe('embedded adapter copies match sdk/src', () => {
  for (const [i, embed] of EMBEDS.entries()) {
    for (const mod of MODULES) {
      it(`embed #${i + 1}: ${mod}`, () => {
        const a = readFileSync(join(SDK, 'src', mod), 'utf8');
        const b = readFileSync(join(embed, 'adapter', mod), 'utf8');
        assert.equal(b, a, `${embed}/adapter/${mod} drifted from sdk/src/${mod}`);
      });
    }

    it(`embed #${i + 1}: boot.mjs is present`, () => {
      assert.ok(existsSync(join(embed, 'adapter', 'boot.mjs')));
    });
  }
});

describe('embedded pages: module graph resolves', () => {
  const IMPORT_RE = /(?:^|\n)\s*import\s[^;]*?from\s+'(\.[^']+)'/g;

  for (const [i, embed] of EMBEDS.entries()) {
    it(`embed #${i + 1}: swap.js imports resolve`, () => {
      const src = readFileSync(join(embed, 'swap.js'), 'utf8');
      const specs = [...src.matchAll(IMPORT_RE)].map((m) => m[1]);
      assert.ok(specs.includes('./adapter/boot.mjs'), 'swap.js must import the adapter boot');
      for (const spec of specs) {
        const target = resolve(dirname(join(embed, 'swap.js')), spec);
        assert.ok(existsSync(target), `unresolved import '${spec}' in ${embed}/swap.js`);
      }
    });

    it(`embed #${i + 1}: swap.html loads swap.js as a module`, () => {
      const html = readFileSync(join(embed, 'swap.html'), 'utf8');
      assert.match(html, /<script type="module" src="swap\.js\?v=\d+"><\/script>/);
      assert.ok(html.includes('id="token-modal"'), 'token modal markup missing');
      assert.ok(html.includes('id="token-input"'));
    });

    it(`embed #${i + 1}: swap.js has no empty catch blocks`, () => {
      const src = readFileSync(join(embed, 'swap.js'), 'utf8');
      assert.doesNotMatch(src, /catch\s*\([^)]*\)\s*\{\s*\}/, 'empty catch in swap.js');
    });
  }
});
