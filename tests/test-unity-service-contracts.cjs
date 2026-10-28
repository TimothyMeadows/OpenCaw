'use strict';

// Every outcome below is SIMULATION evidence. No Unity/SDK/service is loaded.
const assert = require('assert/strict');
const model = require('./lib/unity-service-contracts.cjs');
let checks = 0;
const equal = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const rejects = (action, pattern) => { assert.throws(action, pattern); checks++; };

equal(model.evidenceKind, 'SIMULATION');

// LiveServices: account/environment generations, response ownership, bounded
// retry and exact callback removal after identity replacement/disposal.
{
  const releases = []; const events = []; const listeners = new Set();
  const owner = new model.OwnedLifetime(resource => releases.push(resource));
  rejects(() => owner.begin('read'), /authenticated/);
  owner.select('player-a', 'development');
  const oldRequest = owner.begin('read');
  const remove = owner.subscribe(callback => { listeners.add(callback); return () => listeners.delete(callback); }, value => events.push(value));
  const callback = [...listeners][0]; callback('a');
  owner.select('player-b', 'development');
  equal(listeners.size, 0); callback('stale-a'); remove();
  equal(events, ['a']);
  equal(owner.complete(oldRequest, { id: 'late-resource' }), false);
  equal(releases.map(r => r.id), ['late-resource']);
  const current = owner.begin('read'); equal(owner.complete(current, null), true);
  equal(owner.complete(current, null), false);
  const pending = owner.begin('allocation');
  owner.dispose(); owner.dispose();
  equal(owner.complete(pending, { id: 'after-dispose' }), false);
  equal(releases.map(r => r.id), ['late-resource', 'after-dispose']);
  rejects(() => owner.select('player-c', 'development'), /Disposed/);
  const retry = new model.RetryBudget({ attempts: 3, deadline: 20, baseDelay: 2, maxDelay: 5 });
  equal([retry.next(0), retry.next(2), retry.next(6), retry.next(11)], [2, 4, 5, null]);
  const expired = new model.RetryBudget({ attempts: 5, deadline: 2, baseDelay: 2, maxDelay: 4 });
  equal(expired.next(1), null);
  rejects(() => new model.RetryBudget({ attempts: 0, deadline: 20, baseDelay: 1, maxDelay: 2 }), /budget/);
  rejects(() => new model.RetryBudget({ attempts: 2, deadline: 20, baseDelay: NaN, maxDelay: 2 }), /budget/);
}
console.log('SIMULATION LiveServices: identity generations, late cleanup, subscriptions and retry budgets passed');

// Cleanup adapters can fail independently. All owned cleanup is attempted,
// obsolete callbacks stay inert, and failure identities remain reviewable.
{
  const attempted = []; let stale; let callbacks = 0;
  const owner = new model.OwnedLifetime(resource => {
    attempted.push(resource.id);
    if (resource.id === 'broken-resource') throw new Error('release failed');
  });
  owner.select('player', 'development');
  owner.subscribe(callback => { stale = callback; return () => { attempted.push('broken-handler'); throw new Error('unsubscribe failed'); }; }, () => callbacks++);
  owner.subscribe(() => () => attempted.push('good-handler'), () => callbacks++);
  owner.complete(owner.begin('allocation'), { id: 'broken-resource' });
  owner.complete(owner.begin('allocation'), { id: 'good-resource' });
  const pending = owner.begin('pending');
  rejects(() => owner.dispose(), AggregateError);
  equal(attempted, ['broken-handler', 'good-handler', 'broken-resource', 'good-resource']);
  equal([owner.alive, owner.pending.size, owner.handlers.size, owner.resources.size], [false, 0, 0, 0]);
  equal(pending.cancelled, true);
  equal(owner.cleanupFailures.map(item => item.kind), ['handler', 'resource']);
  equal(owner.cleanupFailures[1].value.id, 'broken-resource');
  stale(); equal(callbacks, 0);
  owner.dispose(); equal(attempted.length, 4);
  equal(owner.cleanupFailures.length, 2);
}
console.log('SIMULATION cleanup: independent adapter failures retain evidence and do not interrupt remaining teardown');

// MultiplayerServices: cancelled late join releases its real-resource analogue;
// membership cannot directly enable gameplay and reconnect repeats readiness.
{
  const releases = []; const session = new model.SessionProtocol(resource => releases.push(resource.id));
  session.select('player-a', 'development');
  const cancelled = session.join(); equal(session.cancel(), true);
  equal(session.joined(cancelled, { id: 'late-session' }), false); equal(releases, ['late-session']);
  equal(session.state, 'idle');
  const active = session.join(); rejects(() => session.join(), /active/);
  equal(session.joined(active, { id: 'active-session' }), true);
  equal(session.state, 'service-member'); rejects(() => session.snapshotReady(), /Transport/);
  session.transportReady(); session.snapshotReady(); equal(session.state, 'playing');
  session.disconnected(50); const reconnect = session.reconnect(49);
  equal(session.reconnected(reconnect), true); equal(session.state, 'service-member');
  session.transportReady(); session.snapshotReady();
  session.disconnected(60); const retiredReconnect = session.reconnect(55);
  session.disconnected(65); const currentReconnect = session.reconnect(60);
  equal(session.reconnected(retiredReconnect), false); equal(session.state, 'reconnecting');
  equal(session.owner.pending.has(currentReconnect), true);
  equal(session.reconnected(currentReconnect), true); equal(session.state, 'service-member');
  session.disconnected(70); rejects(() => session.reconnect(71), /expired/);
  rejects(() => session.reconnect(NaN), /invalid/);
  session.leave(); session.leave(); equal(releases, ['late-session', 'active-session']);
  session.select('player-a', 'development'); const old = session.join();
  session.select('player-b', 'development');
  equal(session.joined(old, { id: 'old-account-session' }), false);
  equal(releases.at(-1), 'old-account-session'); equal(session.state, 'idle');
}
console.log('SIMULATION MultiplayerServices: cancellation, late membership cleanup and reconnect readiness passed');

// VoiceChat: permission and device changes remain distinct from login/channel
// readiness, and obsolete joins cannot reactivate transmission after disposal.
{
  const releases = []; const voice = new model.VoiceProtocol(channel => releases.push(channel.id));
  voice.select('player', 'development'); voice.device = true; voice.muted = false;
  voice.setPermission('denied'); const join = voice.join();
  equal(voice.joined(join, { id: 'channel' }), true); equal(voice.canTransmit(), false);
  voice.setPermission('granted'); equal(voice.canTransmit(), true);
  voice.device = false; equal(voice.canTransmit(), false);
  voice.device = true; voice.muted = true; equal(voice.canTransmit(), false);
  voice.muted = false; voice.setPermission('unknown'); equal(voice.canTransmit(), false);
  voice.setPermission('granted'); const late = voice.join(); voice.dispose();
  equal(voice.joined(late, { id: 'late-channel' }), false);
  equal(releases, ['channel', 'late-channel']); equal(voice.canTransmit(), false);
  rejects(() => voice.setPermission('assumed-granted'), /permission/);
}
console.log('SIMULATION VoiceChat: denied/unknown permission, devices, mute and stale channel teardown passed');

// Purchases: an atomic in-memory journal models the durable boundary. Restart
// from snapshots and replay actual transaction identities across failure points.
{
  const order = { store: 'sandbox', account: 'player', transaction: 'tx-1', product: 'coins', quantity: 10 };
  let journal = new model.PurchaseJournal(); const key = journal.pending(order);
  rejects(() => journal.fulfill(key), /validated/);
  rejects(() => journal.confirmation(key, 'success'), /durable/);
  rejects(() => journal.validate(key, { status: 'valid', key: 'other', product: 'coins', quantity: 10 }), /mismatched/);
  journal.validate(key, { status: 'valid', key, product: 'coins', quantity: 10 });
  journal.failNextCommit = true; rejects(() => journal.fulfill(key), /commit failure/);
  equal(journal.snapshot().balances, {}); equal(journal.snapshot().orders[key].stage, 'validated');
  journal = new model.PurchaseJournal(journal.snapshot()); equal(journal.fulfill(key), true);
  journal = new model.PurchaseJournal(journal.snapshot()); // crash before acknowledgment
  equal(journal.pending(order), key); equal(journal.fulfill(key), false);
  journal.confirmation(key, 'transient-failure'); equal(journal.snapshot().orders[key].stage, 'fulfilled');
  equal(journal.fulfill(key), false); journal.confirmation(key, 'success');
  equal(journal.snapshot().orders[key].stage, 'confirmed');
  equal(journal.snapshot().balances[JSON.stringify(['player', 'coins'])], 10);
  rejects(() => journal.pending({ ...order, quantity: 100 }), /Conflicting/);
  rejects(() => journal.pending({ ...order, account: 'other-player' }), /Conflicting/);
  rejects(() => journal.pending({ ...order, quantity: -1 }), /quantity/);
  const second = journal.pending({ ...order, transaction: 'tx-2' });
  journal.validate(second, { status: 'valid', key: second, product: 'coins', quantity: 10 });
  equal(journal.fulfill(second), true);
  equal(journal.snapshot().balances[JSON.stringify(['player', 'coins'])], 20);
  const anotherStore = journal.pending({ ...order, store: 'other-sandbox' });
  equal(anotherStore === key, false);
}
console.log('SIMULATION Purchases: validation binding, durable commit failure, pending replay and confirmation recovery passed');

// Ads: closed is not rewarded, late reward after close still grants once,
// privacy-denied display is blocked, and destroyed owners require reconciliation.
{
  const grants = []; const ads = new model.RewardProtocol(attempt => grants.push(attempt));
  rejects(() => ads.show('unknown-consent'), /privacy/);
  ads.setPolicy('disabled'); rejects(() => ads.show('denied'), /privacy/);
  ads.setPolicy('contextual'); ads.show('close-first'); ads.event('close-first', 'displayed');
  ads.event('close-first', 'closed'); equal(grants, []);
  equal(ads.event('close-first', 'reward'), 'granted'); equal(ads.event('close-first', 'reward'), 'duplicate');
  ads.show('reward-first'); ads.event('reward-first', 'displayed'); ads.event('reward-first', 'reward'); ads.event('reward-first', 'closed');
  equal(grants, ['close-first', 'reward-first']);
  ads.show('failed'); ads.event('failed', 'failed'); equal(ads.event('failed', 'reward'), 'invalid-reward');
  equal(ads.event('foreign', 'reward'), 'unowned');
  ads.show('pending'); ads.event('pending', 'displayed'); ads.dispose();
  equal(ads.event('pending', 'reward'), 'reconcile-required'); equal(grants.length, 2);
  rejects(() => ads.show('disposed'), /lifetime/);
  const brokenGrant = new model.RewardProtocol(() => { throw new Error('Simulated reward persistence failure'); });
  brokenGrant.setPolicy('contextual'); brokenGrant.show('retry'); brokenGrant.event('retry', 'displayed');
  rejects(() => brokenGrant.event('retry', 'reward'), /persistence/);
  equal(brokenGrant.attempts.get('retry').rewarded, false);
}
console.log('SIMULATION Ads: privacy gating, reward ordering/deduplication, failures and reconciliation passed');

// Optional tooling bridge: targeting and asynchronous completion are protocol
// contracts; this is not a real CLI/Pipeline connection or native readiness test.
{
  const expected = { project: './synthetic-unity-project', instance: 'editor-a', version: '6000.3.0f1' };
  const editor = new model.EditorBinding(expected);
  rejects(() => editor.begin(), /disconnected/);
  rejects(() => editor.connect({ ...expected, instance: 'editor-b' }), /Wrong/);
  rejects(() => editor.connect({ ...expected, project: './other-project' }), /Wrong/);
  editor.connect({ ...expected, safeMode: true, framesAdvancing: true }); rejects(() => editor.begin(), /ready/);
  editor.connect({ ...expected, compiling: true, framesAdvancing: true }); rejects(() => editor.begin(), /ready/);
  editor.connect({ ...expected, importing: true, framesAdvancing: true }); rejects(() => editor.begin(), /ready/);
  editor.connect({ ...expected, framesAdvancing: false }); rejects(() => editor.begin({ requiresFrames: true }), /ready/);
  editor.connect({ ...expected, framesAdvancing: true }); const operation = editor.begin({ requiresFrames: true });
  equal(editor.result(operation, 'pending'), false); editor.disconnect();
  rejects(() => editor.result(operation, 'succeeded'), /Unbound/);
  editor.connect({ ...expected, framesAdvancing: true }); equal(editor.result(operation, 'succeeded'), true);
  rejects(() => editor.result(operation, 'succeeded'), /terminal/);
  rejects(() => editor.result('stale-id', 'succeeded'), /stale/);
  const failed = editor.begin(); equal(editor.result(failed, 'failed'), false);
  const incomplete = editor.begin(); rejects(() => editor.result(incomplete, 'accepted-without-status'), /Incomplete/);
}
console.log('SIMULATION ToolingCli: project/instance targeting, readiness, disconnect and terminal operation checks passed');
console.log(`Unity service protocol simulations passed (${checks} checks); native SDK, service, store and device acceptance NOT RUN.`);
