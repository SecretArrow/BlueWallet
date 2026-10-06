import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Circles bridge coverage + integrity guards (Fase C3).
 *
 * circles.js is reachable from the wallet header but speaks a bridge
 * protocol that the app's local server only partially serves. These tests
 * recompute the gap from the sources so `docs/CIRCLES-GAP.md` cannot rot and
 * a newly-reachable page cannot regress unnoticed.
 */
const SDK = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = resolve(SDK, '..');
const EMBEDS = [
  join(REPO, 'android-native/app/src/main/assets/webcli'),
  join(REPO, 'flutter/assets/webcli'),
];
const ANDROID_SERVER = join(
  REPO,
  'android-native/app/src/main/java/com/octopus/wallet/LocalWebServerService.java',
);
const FLUTTER_SERVER = join(
  REPO,
  'flutter/lib/services/local_web_server_service.dart',
);
const GAP_DOC = join(REPO, 'docs/CIRCLES-GAP.md');

const CIRCLES_USE_RE = /\/api\/(?:circle|program|relay|fhe|keys|send|balance|wallet|tokens)[a-z_/]*/g;

function endpointsUsedByCircles() {
  const src = readFileSync(join(EMBEDS[0], 'circles.js'), 'utf8');
  return new Set(src.match(CIRCLES_USE_RE) || []);
}

function endpointsServedByApp() {
  const served = new Set();
  const patterns = [
    [ANDROID_SERVER, /"\/api\/[a-z_/]+"/g],
    [FLUTTER_SERVER, /'\/api\/[a-z_/]+'/g],
  ];
  for (const [file, re] of patterns) {
    for (const m of readFileSync(file, 'utf8').match(re) || []) {
      served.add(m.replace(/["']/g, ''));
    }
  }
  return served;
}

const missingEndpoints = () => {
  const served = endpointsServedByApp();
  return [...endpointsUsedByCircles()].filter((e) => !served.has(e)).sort();
};

describe('circles bridge endpoint coverage', () => {
  it('the two servers implement the same set (no platform drift)', () => {
    const android = new Set();
    for (const m of readFileSync(ANDROID_SERVER, 'utf8').match(/"\/api\/[a-z_/]+"/g) || []) {
      android.add(m.replace(/"/g, ''));
    }
    const flutter = new Set();
    for (const m of readFileSync(FLUTTER_SERVER, 'utf8').match(/'\/api\/[a-z_/]+'/g) || []) {
      flutter.add(m.replace(/'/g, ''));
    }
    const onlyAndroid = [...android].filter((e) => !flutter.has(e)).sort();
    const onlyFlutter = [...flutter].filter((e) => !android.has(e)).sort();
    assert.deepEqual(
      { onlyAndroid, onlyFlutter },
      { onlyAndroid: [], onlyFlutter: [] },
      'Android and Flutter local servers must expose the same /api surface',
    );
  });

  it('the documented gap matches the measured gap exactly', () => {
    const missing = missingEndpoints();
    const doc = readFileSync(GAP_DOC, 'utf8');
    const documented = [...doc.matchAll(/^- `(\/api\/[^`]+)`$/gm)].map((m) => m[1]).sort();
    assert.deepEqual(
      documented,
      missing,
      `docs/CIRCLES-GAP.md is stale: ${documented.length} listed vs ${missing.length} measured`,
    );
  });

  it('the gap only shrinks (pinned baseline)', () => {
    const missing = missingEndpoints().length;
    // 68 at v0.18.x. Adding a route must come with a doc update; removing one
    // from the page must not silently change the recorded number.
    assert.ok(missing <= 68, `missing endpoints grew: ${missing} > 68 baseline`);
  });

  it('DESKTOP_ONLY_ENDPOINTS in the page are genuinely missing', () => {
    // A stale entry would tell the user to use the desktop build for a
    // feature their build already supports.
    const src = readFileSync(join(EMBEDS[0], 'circles.js'), 'utf8');
    const listMatch = /const DESKTOP_ONLY_ENDPOINTS = \[([\s\S]*?)\]/.exec(src);
    assert.ok(listMatch, 'DESKTOP_ONLY_ENDPOINTS must stay declared');
    const listed = [...listMatch[1].matchAll(/'([^']+)'/g)].map((m) => m[1]).sort();
    const missing = missingEndpoints();
    for (const route of listed) {
      assert.ok(
        missing.includes(route),
        `${route} is listed as desktop-only but the app already serves it`,
      );
    }
    assert.ok(listed.length >= 5, 'the probe list must stay representative');
  });

  it('the page tells the user which build they are on', () => {
    const src = readFileSync(join(EMBEDS[0], 'circles.js'), 'utf8');
    assert.ok(src.includes('/api/relay/health'), 'preflight probe must exist');
    assert.ok(src.includes('partial circle support'), 'preflight must set a visible status');
    assert.ok(src.includes("import('./adapter/boot.mjs')"), 'adapter must be lazily imported');
    // A classic script: flipping to type="module" would hide the top-level
    // `const` bindings of circle_bridge_policy.js / circle_asset_chunks.js.
    assert.doesNotMatch(src, /^\s*import\s+\{/m, 'no static import allowed in a classic script');
    const html = readFileSync(join(EMBEDS[0], 'circles.html'), 'utf8');
    assert.ok(
      /<script src="circles\.js\?v=\d+"><\/script>/.test(html),
      'circles.js must stay a classic script (module would break CircleBridgePolicy)',
    );
    assert.ok(html.includes('id="runtime-note"'), 'preflight needs a note element');
  });

  it('404s name the endpoint and status instead of failing opaquely', () => {
    const src = readFileSync(join(EMBEDS[0], 'circles.js'), 'utf8');
    assert.ok(src.includes('HTTP ${response.status}'), 'status must appear in the error');
    assert.ok(src.includes('non-JSON body'), 'a proxy HTML error page must be labelled');
  });

  for (const [i, embed] of EMBEDS.entries()) {
    it(`embed #${i + 1}: circles.js matches the upstream source it was built from`, () => {
      // The embed is the source of truth for the served page; both platforms
      // must ship the identical file or the bridge behaves differently.
      const a = readFileSync(join(embed, 'circles.js'), 'utf8');
      const b = readFileSync(join(EMBEDS[0], 'circles.js'), 'utf8');
      assert.equal(a, b, `${embed}/circles.js drifted between platforms`);
      assert.ok(existsSync(join(embed, 'adapter', 'boot.mjs')));
    });
  }
});
