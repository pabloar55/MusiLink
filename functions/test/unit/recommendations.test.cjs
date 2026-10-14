const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const { recommendationGenerationCovers } = require('../../lib/recommendations.js');

test('recommendationGenerationCovers deduplicates a generated music version', () => {
  assert.equal(recommendationGenerationCovers({
    recommendationsGeneratedForMusicProfileVersion: 4,
  }, 4), true);
  assert.equal(recommendationGenerationCovers({
    recommendationsGeneratedForMusicProfileVersion: 3,
  }, 4), false);
});


test('recommendationGenerationCovers preserves a newer forced refresh', () => {
  assert.equal(recommendationGenerationCovers({
    recommendationsGeneratedForMusicProfileVersion: 4,
    recommendationsGeneratedAt: Timestamp.fromMillis(100),
  }, 4, 101), false);
  assert.equal(recommendationGenerationCovers({
    recommendationsGeneratedForMusicProfileVersion: 4,
    recommendationsGeneratedAt: Timestamp.fromMillis(101),
  }, 4, 101), true);
});
