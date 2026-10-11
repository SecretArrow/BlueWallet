import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Circles bridge retired with the local-server embed (PR #48).
 *
 * The loopback dApp server is gone: `android-native/.../LocalWebServerService.java`,
 * `flutter/lib/services/local_web_server_service.dart`, and both `webcli`
 * embeds (including `circles.js`) were deleted, so the endpoint-coverage,
 * DESKTOP_ONLY, preflight-probe, and module-parity tests that read those
 * files were removed — they failed with ENOENT once the sources disappeared.
 * What remains below are absence guards: the bridge must stay deleted and no
 * cleartext exception for the loopback server may come back.
 *
 * `docs/CIRCLES-GAP.md` is kept as a historical record of the last measured
 * gap; it is no longer recomputed from the sources.
 */
const SDK = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = resolve(SDK, '..');
const CIRCLES_EMBEDS = [
  join(REPO, 'android-native/app/src/main/assets/webcli/circles.js'),
  join(REPO, 'flutter/assets/webcli/circles.js'),
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
const FLUTTER_MANIFEST = join(REPO, 'flutter/android/app/src/main/AndroidManifest.xml');
const FLUTTER_NSC = join(
  REPO,
  'flutter/android/app/src/main/res/xml/network_security_config.xml',
);
const ANDROID_NSC = join(
  REPO,
  'android-native/app/src/main/res/xml/network_security_config.xml',
);

const CLEARTEXT_DOMAIN_CONFIG_RE =
  /<domain-config[^>]*cleartextTrafficPermitted="true"[^>]*>([\s\S]*?)<\/domain-config>/g;

function cleartextDomainConfigBodies(nsc) {
  return [...nsc.matchAll(CLEARTEXT_DOMAIN_CONFIG_RE)].map((m) => m[1]);
}

describe('circles bridge retired (local server removed)', () => {
  it('the circles embeds stay deleted on both platforms', () => {
    for (const file of CIRCLES_EMBEDS) {
      assert.ok(!existsSync(file), `${file} must stay deleted (PR #48)`);
    }
  });

  it('the local-server implementations stay deleted', () => {
    for (const file of [ANDROID_SERVER, FLUTTER_SERVER]) {
      assert.ok(!existsSync(file), `${file} must stay deleted (PR #48)`);
    }
  });

  it('the gap inventory is kept as a historical record, not a live contract', () => {
    const doc = readFileSync(GAP_DOC, 'utf8');
    assert.match(doc, /PR #48/, 'the doc must record when the bridge was retired');
    assert.match(doc, /historis|historic/i, 'the doc must say the inventory is historical');
  });
});

describe('no cleartext exceptions (loopback server removed)', () => {
  it('the Flutter app still wires the network security config (now HTTPS-only)', () => {
    const manifest = readFileSync(FLUTTER_MANIFEST, 'utf8');
    assert.match(
      manifest,
      /android:networkSecurityConfig="@xml\/network_security_config"/,
      'the manifest must keep pointing at the HTTPS-only config (fail closed)',
    );
  });

  it('the Flutter config has no cleartext exception left', () => {
    const nsc = readFileSync(FLUTTER_NSC, 'utf8');
    assert.equal(
      cleartextDomainConfigBodies(nsc).length,
      0,
      'flutter NSC must not permit cleartext anywhere after the loopback server removal',
    );
    assert.match(
      nsc,
      /<base-config cleartextTrafficPermitted="false">/,
      'flutter base-config must stay HTTPS-only (fail closed)',
    );
  });

  it('base-config stays HTTPS-only on both platforms', () => {
    for (const file of [FLUTTER_NSC, ANDROID_NSC]) {
      assert.match(
        readFileSync(file, 'utf8'),
        /<base-config cleartextTrafficPermitted="false">/,
        `${file} base-config must stay HTTPS-only`,
      );
    }
  });

  it('the android-native config has no cleartext exception left', () => {
    const nsc = readFileSync(ANDROID_NSC, 'utf8');
    assert.equal(
      cleartextDomainConfigBodies(nsc).length,
      0,
      'android-native NSC must not permit cleartext anywhere after the loopback server removal',
    );
    assert.match(
      nsc,
      /<base-config cleartextTrafficPermitted="false">/,
      'android-native base-config must stay HTTPS-only (fail closed)',
    );
  });
});
