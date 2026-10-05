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

    // ── bridge (Fase C2) ────────────────────────────────────────────

    it(`embed #${i + 1}: bridge.js imports resolve`, () => {
      const src = readFileSync(join(embed, 'bridge.js'), 'utf8');
      const specs = [...src.matchAll(IMPORT_RE)].map((m) => m[1]);
      assert.ok(specs.includes('./adapter/boot.mjs'), 'bridge.js must import the adapter boot');
      for (const spec of specs) {
        const target = resolve(dirname(join(embed, 'bridge.js')), spec);
        assert.ok(existsSync(target), `unresolved import '${spec}' in ${embed}/bridge.js`);
      }
    });

    it(`embed #${i + 1}: bridge.html loads bridge.js as a module`, () => {
      const html = readFileSync(join(embed, 'bridge.html'), 'utf8');
      assert.match(html, /<script type="module" src="bridge\.js\?v=\d+"><\/script>/);
      assert.ok(html.includes('id="token-modal"'));
      assert.ok(html.includes('id="token-input"'));
      // Both modal buttons must be wired through the shared dispatcher.
      assert.ok(html.includes('data-action="saveToken"'));
      assert.ok(html.includes('data-action="cancelToken"'));
    });

    it(`embed #${i + 1}: bridge.js routes Octra reads/writes through the adapter`, () => {
      const src = readFileSync(join(embed, 'bridge.js'), 'utf8');
      assert.ok(src.includes('adapter.getBalance()'), 'balance must use the adapter');
      assert.ok(
        src.includes("method: 'lock_to_eth'"),
        'lock_to_eth must go through callContract',
      );
      assert.ok(src.includes('adapter.getTransaction('), 'epoch lookup must use the adapter');
      // Regression: these used to call routes the local server never had.
      assert.doesNotMatch(src, /wcli\('GET', '\/(balance|transaction)/, 'direct /balance or /transaction fetch left');
      // Regression: a hardcoded OU can underpay the lock tx.
      assert.doesNotMatch(src, /ou:\s*'\d+'/, 'hardcoded ou left in bridge.js');
    });

    it(`embed #${i + 1}: bridge.js empty catches do not grow`, () => {
      // 13 pre-existing upstream catches (localStorage guards, EVM receipt
      // and signer pollers) are pinned here so the count can only shrink as
      // each flow is mapped — never grow silently.
      const src = readFileSync(join(embed, 'bridge.js'), 'utf8');
      const empties = (src.match(/catch\s*\([^)]*\)\s*\{\s*\}/g) || []).length;
      assert.ok(
        empties <= 13,
        `empty catch blocks grew: ${empties} > 13 baseline (map and fix them)`,
      );
    });
  }
});
