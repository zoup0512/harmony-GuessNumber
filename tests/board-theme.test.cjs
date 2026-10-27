'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const themeSource = read('common/Theme.ets');
const theme = Object.fromEntries([...themeSource.matchAll(/static readonly (\w+): string = '([^']+)'/g)]
  .map(match => [match[1], match[2]]));

function luminance(hex) {
  const linear = [1, 3, 5].map(offset => parseInt(hex.slice(offset, offset + 2), 16) / 255)
    .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}

function contrast(foreground, background) {
  const [dark, light] = [luminance(foreground), luminance(background)].sort((a, b) => a - b);
  return (light + 0.05) / (dark + 0.05);
}

test('board pages only reference defined semantic colors and contain no emoji decoration', () => {
  for (const file of ['pages/Index.ets', 'views/GamePage.ets', 'views/TutorialPage.ets', 'common/BoardIcon.ets']) {
    const source = read(file);
    for (const [, name] of source.matchAll(/Theme\.(\w+)/g)) {
      assert.match(themeSource, new RegExp(`static readonly ${name}:`), `${file}: missing ${name}`);
    }
    assert.doesNotMatch(source, /Theme\.GOLD|#[0-9a-f]{6}\b|\.linearGradient\(/i, file);
    assert.doesNotMatch(source, /\p{Extended_Pictographic}|\uFE0F|\u200D/u, file);
  }
});

test('small text and feedback colors meet normal-text contrast on their surfaces', () => {
  for (const foreground of ['TEXT', 'TEXT_SUB', 'TEXT_FAINT']) {
    for (const background of ['BG_TOP', 'CARD', 'CARD_STRONG', 'RED_BG']) {
      assert.ok(contrast(theme[foreground], theme[background]) >= 4.5, `${foreground} on ${background}`);
    }
  }
  for (const [foreground, background] of [
    ['ON_PRIMARY', 'PRIMARY'],
    ['POSITION_EXACT', 'POSITION_EXACT_BG'],
    ['POSITION_MISPLACED', 'POSITION_MISPLACED_BG'],
  ]) assert.ok(contrast(theme[foreground], theme[background]) >= 4.5, `${foreground} on ${background}`);
});

test('AI and hint controls reflect the final-attempt restriction', () => {
  const source = read('views/GamePage.ets');
  assert.match(source, /return !this\.finished && this\.attemptsLeft > 1 && this\.aiUsesLeft > 0/);
  assert.match(source, /return !this\.finished && this\.attemptsLeft > 1 && !this\.hintUsed/);
  assert.match(source, /\.enabled\(this\.aiAvailable\(\)\)/);
  assert.match(source, /\.enabled\(this\.hintAvailable\(\)\)/);
  assert.match(source, /填入并提交/);
});

test('five-digit tiles fit the supported compact layout budget', () => {
  const source = read('views/GamePage.ets');
  assert.match(source, /this\.digits === 5 \? 48 : 54/);
  assert.match(source, /this\.digits === 5 \? 38 : 44/);
  assert.match(source, /this\.digits === 5 \? 34 : 40/);
  assert.ok(5 * 48 + 4 * 8 <= 320 - 36);
  assert.ok(5 * 38 + 4 * 6 <= 320 * 0.84 - 48);
  assert.ok(5 * 34 + 4 * 6 <= 320 - 44 - 28);
});
