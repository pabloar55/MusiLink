const assert = require('node:assert/strict');
const { test } = require('node:test');
const { fetchLastFm } = require('../../lib/lastfm_request.js');

test('Last.fm requests preserve the requested limit and fetch again on repeated calls', async (t) => {
  const requests = [];
  t.mock.method(global, 'fetch', async (input, init) => {
    requests.push(new URL(input));
    assert.ok(init.signal instanceof AbortSignal);
    assert.equal(init.headers['User-Agent'], 'MusiLink/1.0');
    return Response.json({ similarartists: { artist: [] } });
  });
  for (let i = 0; i < 2; i++) {
    await fetchLastFm('artist.getSimilar', 'Muse', 'test-key', 1);
  }
  await fetchLastFm('artist.getTopTags', 'Muse', 'test-key');
  assert.equal(requests.length, 3);
  assert.deepEqual(requests.map((url) => url.searchParams.get('limit')), ['1', '1', null]);
  assert.equal(requests[0].searchParams.get('artist'), 'Muse');
});

test('network, HTTP, API and JSON errors retain their callable error codes', async (t) => {
  const cases = [
    [() => { throw new Error('offline'); }, 'unavailable'],
    [() => new Response('', { status: 503 }), 'unavailable'],
    [() => new Response('', { status: 429 }), 'resource-exhausted'],
    [() => Response.json({ error: 29 }), 'resource-exhausted'],
    [() => Response.json({ error: 11 }), 'unavailable'],
    [() => new Response('broken JSON'), 'unavailable'],
  ];
  for (const [response, code] of cases) {
    const mocked = t.mock.method(global, 'fetch', async () => response());
    await assert.rejects(fetchLastFm('artist.getSimilar', 'Muse', 'test-key'), { code });
    mocked.mock.restore();
  }
});
