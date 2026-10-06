import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Shipped-version guards.
 *
 * Both apps must report the same version, and it must come from
 * `version.properties` / `pubspec.yaml` rather than a literal in the build
 * script. This was a real defect: the Android build hardcoded
 * `"0.14.${code}-alpha"`, so v0.15.0 … v0.17.1-alpha all shipped as 0.14.x.
 */
const SDK = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = resolve(SDK, '..');

function readProps(file) {
  const out = {};
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    out[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
  }
  return out;
}

const androidProps = readProps(join(REPO, 'android-native/version.properties'));
const gradle = readFileSync(join(REPO, 'android-native/app/build.gradle'), 'utf8');
const pubspec = readFileSync(join(REPO, 'flutter/pubspec.yaml'), 'utf8');

function flutterVersion() {
  const m = /^version:\s*(\S+)\+(\d+)\s*$/m.exec(pubspec);
  assert.ok(m, 'pubspec.yaml must declare version: <name>+<build>');
  return { name: m[1], build: Number(m[2]) };
}

describe('shipped version', () => {
  it('both apps declare the same version name', () => {
    assert.equal(flutterVersion().name, androidProps.VERSION_NAME);
  });

  it('versionName comes from version.properties, not a literal', () => {
    assert.match(gradle, /versionName configuredVersionName/);
    assert.doesNotMatch(
      gradle,
      /versionName\s+"[\d.]+\$\{/,
      'a literal version template in build.gradle will drift from the tag again',
    );
  });

  it('build numbers stay monotonic across both apps', () => {
    // Play and Android both order by versionCode/build number; a lower number
    // makes the release invisible to updaters.
    const androidCode = Number(androidProps.VERSION_CODE);
    assert.ok(Number.isInteger(androidCode) && androidCode > 0);
    assert.equal(
      androidCode,
      flutterVersion().build,
      'android VERSION_CODE and flutter build number must match so the two apps are the same build',
    );
  });

  it('the version matches the documented sunset schedule', () => {
    // Legacy dialect sunset is planned for v0.19.0 (docs/ADAPTER.md), so the
    // version must not already be past it.
    const majorMinor = /^0\.(\d+)\./.exec(androidProps.VERSION_NAME);
    assert.ok(majorMinor, `unexpected version shape: ${androidProps.VERSION_NAME}`);
    assert.ok(
      Number(majorMinor[1]) < 19,
      'the legacy dialect is sunset at v0.19.0; do not ship past it with the legacy provider still live',
    );
  });
});
