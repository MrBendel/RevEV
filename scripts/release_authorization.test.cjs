const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { resolve } = require('node:path');

// Exercise the actual inline Actions script with mocked GitHub responses.
const workflow = readFileSync(resolve(__dirname, '../.github/workflows/play-internal.yml'), 'utf8');
const script = workflow.split('          script: |')[1].split('\n  release:')[0]
  .split('\n').map(line => line.replace(/^            /, '')).join('\n');
const authorize = new (Object.getPrototypeOf(async function () {}).constructor)(
  'github', 'context', 'core', 'process', script);

async function run({ permission = 'write', ready = 'true', event = 'issue_comment',
  ref = 'refs/heads/main', publish = 'true', pr = {} } = {}) {
  const outputs = {};
  await authorize({ rest: {
    repos: { getCollaboratorPermissionLevel: async () => ({ data: { permission } }) },
    pulls: { get: async () => ({ data: {
      state: 'open', merged: false,
      head: { repo: { full_name: 'MrBendel/RevEV' }, sha: 'pr-head' },
      base: { ref: 'main' }, merge_commit_sha: 'merge-commit', ...pr,
    } }) },
  } }, { repo: { owner: 'MrBendel', repo: 'RevEV' }, actor: 'maintainer',
    sha: 'event-commit', eventName: event, ref, issue: { number: 2 } },
  { setOutput: (key, value) => { outputs[key] = value; },
    notice: () => {}, summary: { addRaw: () => ({ write: async () => {} }) } },
  { env: { PLAY_READY: ready, PUBLISH: publish, RELEASE_STATUS: 'draft' } });
  return outputs;
}

test('open PR uses exact head and completed internal release', async () => {
  assert.deepEqual(await run(), { ref: 'pr-head', publish: 'true', status: 'completed' });
});
test('merged PR uses exact merge commit', async () => {
  assert.equal((await run({ pr: { state: 'closed', merged: true } })).ref, 'merge-commit');
});
test('closed unmerged PR is rejected', async () => {
  await assert.rejects(run({ pr: { state: 'closed' } }), /closed unmerged/);
});
test('fork PR is rejected even after merge', async () => {
  await assert.rejects(run({ pr: { merged: true, head: { repo: { full_name: 'other/RevEV' } } } }), /forks/);
});
test('missing source repository is rejected', async () => {
  await assert.rejects(run({ pr: { head: { repo: null } } }), /forks/);
});
test('merge outside main is rejected', async () => {
  await assert.rejects(run({ pr: { merged: true, base: { ref: 'other' } } }), /merge into main/);
});
test('missing merge commit is rejected', async () => {
  await assert.rejects(run({ pr: { merged: true, merge_commit_sha: null } }), /merge commit/);
});
test('read-only caller is rejected', async () => {
  await assert.rejects(run({ permission: 'read' }), /maintainers/);
});
test('disabled publishing blocks both PR and manual publishing', async () => {
  await assert.rejects(run({ ready: 'false' }), /Play publishing is disabled/);
  await assert.rejects(run({ ready: 'false', event: 'workflow_dispatch' }), /Play publishing is disabled/);
});
test('manual build-only remains available while publishing is disabled', async () => {
  assert.deepEqual(await run({ event: 'workflow_dispatch', ready: 'false', publish: 'false' }),
    { ref: 'event-commit', publish: 'false', status: 'draft' });
});
test('manual release outside main is rejected', async () => {
  await assert.rejects(run({ event: 'workflow_dispatch', ref: 'refs/heads/other' }), /from main/);
});
