/*
 * Debug signing regression test; run from the repository root:
 *   node --test tests/signing-config.test.cjs
 * No DevEco, device, network, or generated build files are needed.
 * Guards the cross-machine signing contract: repository-relative paths, the
 * decryption material DevEco needs for the encrypted passwords, and a profile
 * that still matches this app's bundle name.
 */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const root = path.resolve(__dirname, '..');
const buildProfilePath = path.join(root, 'build-profile.json5');
const appScopePath = path.join(root, 'AppScope/app.json5');

const readJson5 = file => {
  // These files only use JSON syntax; JSON.parse keeps the test dependency-free.
  return JSON.parse(fs.readFileSync(file, 'utf8'));
};

// The .p7b is a PKCS#7 SignedData whose content is the profile JSON.
// Extract it by locating the JSON object instead of shipping an ASN.1 parser.
function readProfile(profilePath) {
  const der = fs.readFileSync(profilePath);
  const raw = der.toString('latin1');
  const start = raw.indexOf('{"version-name"');
  assert.notEqual(start, -1, 'profile payload JSON not found');
  let depth = 0;
  let end = -1;
  for (let index = start; index < raw.length; index += 1) {
    const char = raw[index];
    if (char === '{') depth += 1;
    if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        end = index + 1;
        break;
      }
    }
  }
  assert.notEqual(end, -1, 'profile payload JSON is truncated');
  return JSON.parse(raw.slice(start, end));
}

test('debug signing is repository-relative so any machine signs identically', () => {
  const { app: build } = readJson5(buildProfilePath);
  const { app: appScope } = readJson5(appScopePath);
  const product = build.products.find(entry => entry.name === 'default');
  assert.ok(product, 'default product is missing');
  const config = build.signingConfigs.find(entry => entry.name === product.signingConfig);
  assert.ok(config, `signing config ${product.signingConfig} is missing`);

  const { material } = config;
  assert.equal(config.type, 'HarmonyOS');
  assert.equal(material.keyAlias, 'debugKey');
  assert.match(material.keyPassword, /^[0-9A-F]+$/i, 'encrypted keyPassword is missing');
  assert.match(material.storePassword, /^[0-9A-F]+$/i, 'encrypted storePassword is missing');

  for (const key of ['certpath', 'profile', 'storeFile']) {
    const value = material[key];
    assert.ok(value, `material.${key} is missing`);
    assert.doesNotMatch(value, /^[A-Za-z]:|^\\\\|^~/, `material.${key} must not be machine-specific: ${value}`);
    const resolved = path.resolve(root, value);
    assert.ok(resolved.startsWith(root + path.sep), `material.${key} escapes the repository: ${value}`);
    assert.ok(fs.existsSync(resolved), `material.${key} is missing: ${value}`);
  }

  // DevEco reads <storeFile dir>/material to decrypt the passwords above.
  const materialDir = path.join(path.dirname(path.resolve(root, material.storeFile)), 'material');
  assert.ok(fs.existsSync(materialDir), `secret-store material is missing: ${materialDir}`);
  assert.ok(fs.readdirSync(materialDir, { recursive: true }).length > 0, 'secret-store material is empty');

  const profile = readProfile(path.resolve(root, material.profile));
  assert.equal(profile.type, 'debug', 'profile must be a debug profile, not release');
  assert.equal(profile['bundle-info']['bundle-name'], appScope.bundleName, 'profile bundle name does not match AppScope/app.json5');
  assert.equal(profile['bundle-info'].apl, 'normal');

  const expiresAt = new Date(profile.validity['not-after'] * 1000);
  assert.ok(expiresAt > new Date(), `debug profile expired on ${expiresAt.toISOString().slice(0, 10)}; renew it in AppGallery Connect`);
});

test('signing material stays in the versioned keystore/debug directory', () => {
  const { app: build } = readJson5(buildProfilePath);
  for (const config of build.signingConfigs) {
    for (const key of ['certpath', 'profile', 'storeFile']) {
      assert.match(config.material[key], /^keystore\/debug\//, `${config.name}: ${key} should live under keystore/debug/`);
    }
  }
});
