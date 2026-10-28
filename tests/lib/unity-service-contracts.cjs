'use strict';

// SIMULATION ONLY. These are executable application protocol models with
// synthetic adapter outcomes. They do not load Unity or invoke any real SDK.
const crypto = require('crypto');
const path = require('path');
const clone = value => JSON.parse(JSON.stringify(value));
function text(value, label) {
  if (typeof value !== 'string' || !value.trim() || /[\x00-\x1f]/.test(value)) throw new Error('Invalid ' + label);
  return value;
}

class OwnedLifetime {
  constructor(release) {
    if (typeof release !== 'function') throw new Error('A release adapter is required');
    this.release = release; this.generation = 0; this.pending = new Set();
    this.resources = new Set(); this.handlers = new Set(); this.identity = null; this.alive = true;
  }
  select(identity, environment) {
    if (!this.alive) throw new Error('Disposed owner');
    text(identity, 'identity'); text(environment, 'environment');
    this.invalidate(); this.identity = { identity, environment };
  }
  invalidate() {
    this.generation++;
    for (const token of this.pending) token.cancelled = true;
    this.pending.clear();
    const handlers = [...this.handlers], resources = [...this.resources];
    this.handlers.clear();
    this.resources.clear();
    this.identity = null;
    const failures = [];
    for (const handler of handlers) {
      try { handler.unsubscribe(); } catch (error) { failures.push({ kind: 'handler', value: handler, error }); }
    }
    for (const resource of resources) {
      try { this.release(resource); } catch (error) { failures.push({ kind: 'resource', value: resource, error }); }
    }
    this.cleanupFailures = failures;
    if (failures.length) throw new AggregateError(failures.map(item => item.error), 'Owned lifetime cleanup failed; retained failure identities require reconciliation');
  }
  begin(kind) {
    if (!this.alive || !this.identity) throw new Error('No active authenticated identity');
    const token = { generation: this.generation, kind: text(kind, 'operation kind'), cancelled: false, consumed: false };
    this.pending.add(token); return token;
  }
  cancel(token) {
    if (!this.pending.has(token)) return false;
    token.cancelled = true; this.pending.delete(token); return true;
  }
  complete(token, resource) {
    // A late successful allocation still has an owner responsible for release.
    if (!token || token.consumed) return false;
    token.consumed = true;
    const eligible = this.alive && this.pending.has(token) && !token.cancelled && token.generation === this.generation;
    this.pending.delete(token);
    if (!eligible) { if (resource != null) this.release(resource); return false; }
    if (resource != null) this.resources.add(resource);
    return true;
  }
  subscribe(adapter, listener) {
    if (!this.alive || !this.identity) throw new Error('No active authenticated identity');
    const generation = this.generation;
    let active = true;
    const wrapped = (...args) => { if (active && this.alive && generation === this.generation) listener(...args); };
    const remove = adapter(wrapped);
    if (typeof remove !== 'function') throw new Error('Subscription requires explicit cleanup');
    const entry = { unsubscribe: () => { if (!active) return; active = false; remove(); } };
    this.handlers.add(entry);
    return () => { entry.unsubscribe(); this.handlers.delete(entry); };
  }
  dispose() { if (this.alive) { this.alive = false; this.invalidate(); } }
}

class RetryBudget {
  constructor({ attempts, deadline, baseDelay, maxDelay }) {
    if (!Number.isInteger(attempts) || attempts < 1 || !Number.isFinite(deadline) || !Number.isFinite(baseDelay) || !Number.isFinite(maxDelay) || baseDelay <= 0 || maxDelay < baseDelay) throw new Error('Invalid retry budget');
    Object.assign(this, { attempts, deadline, baseDelay, maxDelay }); this.used = 0;
  }
  next(now) {
    if (!Number.isFinite(now)) throw new Error('Invalid retry clock');
    const delay = Math.min(this.maxDelay, this.baseDelay * 2 ** this.used);
    if (this.used >= this.attempts || now + delay > this.deadline) return null;
    this.used++; return delay;
  }
}

class SessionProtocol {
  constructor(release) { this.owner = new OwnedLifetime(release); this.state = 'signed-out'; this.session = null; }
  select(identity, environment) { this.owner.select(identity, environment); this.session = null; this.state = 'idle'; }
  join() {
    if (!['idle', 'failed'].includes(this.state)) throw new Error('Join already active or session already owned');
    this.state = 'joining'; this.attempt = this.owner.begin('join'); return this.attempt;
  }
  cancel() {
    if (this.state !== 'joining') return false;
    this.owner.cancel(this.attempt); this.state = 'idle'; return true;
  }
  joined(token, session) {
    text(session && session.id, 'session id');
    if (!this.owner.complete(token, session)) return false;
    this.session = session; this.state = 'service-member'; return true;
  }
  transportReady() { if (this.state !== 'service-member') throw new Error('Membership is not ready'); this.state = 'transport-ready'; }
  snapshotReady() { if (this.state !== 'transport-ready') throw new Error('Transport is not ready'); this.state = 'playing'; }
  disconnected(deadline) {
    if (!this.session || !Number.isFinite(deadline)) throw new Error('No retained session or deadline');
    if (this.attempt) this.owner.cancel(this.attempt);
    this.attempt = null;
    this.deadline = deadline; this.state = 'disconnected';
  }
  reconnect(now) {
    if (this.state !== 'disconnected' || !Number.isFinite(now) || now > this.deadline) throw new Error('Reconnect retention expired or state invalid');
    this.state = 'reconnecting'; this.attempt = this.owner.begin('reconnect'); return this.attempt;
  }
  reconnected(token) {
    if (this.state !== 'reconnecting' || token !== this.attempt) return false;
    if (!this.owner.complete(token, null)) return false;
    this.attempt = null; this.state = 'service-member'; return true;
  }
  leave() { this.owner.invalidate(); this.session = null; this.state = 'signed-out'; }
}

function orderKey(order) {
  text(order.account, 'account');
  return JSON.stringify([text(order.store, 'store'), text(order.transaction, 'transaction')]);
}

class PurchaseJournal {
  constructor(snapshot = { orders: {}, balances: {} }) {
    // This in-memory transaction store models durable snapshots. It is not a
    // production database, receipt validator or persistence implementation.
    this.store = clone(snapshot); this.failNextCommit = false;
  }
  transact(operation) {
    const working = clone(this.store); const result = operation(working);
    if (this.failNextCommit) { this.failNextCommit = false; throw new Error('Simulated durable commit failure'); }
    this.store = working; return result;
  }
  pending(order) {
    const key = orderKey(order);
    text(order.product, 'product');
    if (!Number.isSafeInteger(order.quantity) || order.quantity < 1 || order.quantity > 1000000) throw new Error('Invalid quantity');
    return this.transact(store => {
      const existing = store.orders[key];
      if (existing) {
        if (existing.account !== order.account || existing.product !== order.product || existing.quantity !== order.quantity) throw new Error('Conflicting transaction replay');
        return key;
      }
      store.orders[key] = { ...clone(order), stage: 'unverified' }; return key;
    });
  }
  validate(key, verdict) {
    return this.transact(store => {
      const order = store.orders[key];
      if (!order || !verdict || verdict.status !== 'valid' || verdict.key !== key || verdict.product !== order.product || verdict.quantity !== order.quantity) throw new Error('Unverified or mismatched receipt verdict');
      if (order.stage === 'unverified') order.stage = 'validated';
    });
  }
  fulfill(key) {
    return this.transact(store => {
      const order = store.orders[key];
      if (!order || order.stage === 'unverified') throw new Error('Fulfillment requires validated transaction');
      if (['fulfilled', 'confirmed'].includes(order.stage)) return false;
      const entitlement = JSON.stringify([order.account, order.product]);
      store.balances[entitlement] = (store.balances[entitlement] || 0) + order.quantity;
      order.stage = 'fulfilled'; return true;
    });
  }
  confirmation(key, outcome) {
    return this.transact(store => {
      const order = store.orders[key];
      if (!order || !['fulfilled', 'confirmed'].includes(order.stage)) throw new Error('Confirmation before durable fulfillment');
      if (!['success', 'transient-failure'].includes(outcome)) throw new Error('Unknown confirmation outcome');
      if (outcome === 'success') order.stage = 'confirmed';
    });
  }
  snapshot() { return clone(this.store); }
}

class VoiceProtocol {
  constructor(release) {
    this.owner = new OwnedLifetime(release); this.permission = 'unknown'; this.device = false;
    this.muted = true; this.connected = false;
  }
  select(identity, environment) { this.owner.select(identity, environment); this.connected = false; }
  setPermission(value) { if (!['unknown', 'denied', 'granted'].includes(value)) throw new Error('Invalid microphone permission'); this.permission = value; }
  join() { return this.owner.begin('voice-join'); }
  joined(token, channel) { if (!this.owner.complete(token, channel)) return false; this.connected = true; return true; }
  canTransmit() { return this.owner.alive && this.connected && this.permission === 'granted' && this.device && !this.muted; }
  dispose() { this.connected = false; this.owner.dispose(); }
}

class RewardProtocol {
  constructor(grant) { this.grant = grant; this.policy = 'unknown'; this.attempts = new Map(); this.alive = true; }
  setPolicy(value) { if (!['unknown', 'disabled', 'contextual', 'personalized'].includes(value)) throw new Error('Invalid privacy policy'); this.policy = value; }
  show(attempt) {
    if (!this.alive || !['contextual', 'personalized'].includes(this.policy)) throw new Error('Ad display is disabled by privacy policy or owner lifetime');
    text(attempt, 'ad attempt');
    if (this.attempts.has(attempt)) throw new Error('Duplicate ad attempt');
    this.attempts.set(attempt, { displayed: false, closed: false, rewarded: false, failed: false });
  }
  event(attempt, kind) {
    const state = this.attempts.get(attempt);
    if (!state) return 'unowned';
    if (!this.alive) return kind === 'reward' ? 'reconcile-required' : 'disposed';
    if (kind === 'displayed' && !state.failed) state.displayed = true;
    else if (kind === 'failed') state.failed = true;
    else if (kind === 'closed') state.closed = true;
    else if (kind === 'reward') {
      if (!state.displayed || state.failed) return 'invalid-reward';
      if (state.rewarded) return 'duplicate';
      this.grant(attempt); state.rewarded = true; return 'granted';
    } else return 'ignored';
    return 'observed';
  }
  dispose() { this.alive = false; }
}

class EditorBinding {
  constructor(expected) { this.expected = { ...expected, project: path.resolve(expected.project) }; this.connected = false; this.operations = new Map(); }
  connect(observed) {
    if (path.resolve(observed.project) !== this.expected.project || observed.instance !== this.expected.instance || observed.version !== this.expected.version) throw new Error('Wrong project or Editor instance');
    this.connected = true; this.observed = { ...observed };
  }
  begin({ requiresFrames = false } = {}) {
    if (!this.connected || this.observed.safeMode || this.observed.compiling || this.observed.importing || (requiresFrames && !this.observed.framesAdvancing)) throw new Error('Editor is disconnected or not ready');
    const id = crypto.randomUUID(); this.operations.set(id, 'pending'); return id;
  }
  result(id, state) {
    if (!this.connected || !this.operations.has(id)) throw new Error('Unbound or stale operation');
    if (!['pending', 'succeeded', 'failed'].includes(state)) throw new Error('Incomplete or unknown operation state');
    if (this.operations.get(id) !== 'pending') throw new Error('Operation is already terminal');
    this.operations.set(id, state); return state === 'succeeded';
  }
  disconnect() { this.connected = false; }
}

module.exports = { evidenceKind: 'SIMULATION', OwnedLifetime, RetryBudget, SessionProtocol, PurchaseJournal, VoiceProtocol, RewardProtocol, EditorBinding };
