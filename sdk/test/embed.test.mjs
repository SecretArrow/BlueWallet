import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * No-stale-embeds + sdk module-graph guards.
 *
 * The Local Web Server was removed (PR #48) and with it the vendored
 * embedded copies at `android-native/app/src/main/assets/webcli/` and
 * `flutter/assets/webcli/` were deleted. This file no longer reads those
 * directories — doing so fails CI with ENOENT.
 *
 * It now guards the new reality:
 *   1. the removed embed directories stay removed (a stale vendored copy
 *      must not be reintroduced silently), and
 *   2. the sdk remains a valid JS package: every module in sdk/src exists
 *      and every relative import between modules resolves on disk.
 */
const SDK = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = resolve(SDK, '..');
const REMOVED_EMBEDS = [
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
// boot.mjs lives next to the sdk modules only if a page entry-point needs it.
const OPTIONAL_MODULES = ['boot.mjs'];

describe('removed embeds stay removed', () => {
  for (const [i, embed] of REMOVED_EMBEDS.entries()) {
    it(`embed dir #${i + 1} does not exist: ${embed}`, () => {
      assert.ok(
        !existsSync(embed),
        `stale embed reintroduced at ${embed} — vendored webcli copies were deleted with the Local Web Server (PR #48)`,
      );
    });
  }
});

describe('sdk module graph resolves', () => {
  const IMPORT_RE = /(?:^|\n)\s*import\s[^;]*?from\s+'(\.[^']+)'/g;

  for (const mod of MODULES) {
    it(`sdk/src/${mod} exists and is non-empty`, () => {
      const file = join(SDK, 'src', mod);
      assert.ok(existsSync(file), `missing sdk module: src/${mod}`);
      const src = readFileSync(file, 'utf8');
      assert.ok(src.length > 0, `empty sdk module: src/${mod}`);
    });

    it(`sdk/src/${mod} relative imports resolve`, () => {
      const file = join(SDK, 'src', mod);
      const src = readFileSync(file, 'utf8');
      const specs = [...src.matchAll(IMPORT_RE)].map((m) => m[1]);
      for (const spec of specs) {
        const target = resolve(dirname(file), spec);
        assert.ok(existsSync(target), `unresolved import '${spec}' in sdk/src/${mod}`);
      }
    });
  }

  for (const mod of OPTIONAL_MODULES) {
    it(`sdk/src/${mod} relative imports resolve (if present)`, () => {
      const file = join(SDK, 'src', mod);
      if (!existsSync(file)) return;
      const src = readFileSync(file, 'utf8');
      const specs = [...src.matchAll(IMPORT_RE)].map((m) => m[1]);
      for (const spec of specs) {
        const target = resolve(dirname(file), spec);
        assert.ok(existsSync(target), `unresolved import '${spec}' in sdk/src/${mod}`);
      }
    });
  }
});
