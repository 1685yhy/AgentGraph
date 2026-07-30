/* ═══════ Game Programming Patterns ═══════
 * Battle-tested design patterns for 2D games.
 * Inspired by: Robert Nystrom's "Game Programming Patterns",
 *              github.com/QianMo/Unity-Design-Pattern (4.4K stars)
 *
 * Zero dependencies. Works in browser, Phaser, or vanilla JS.
 */

// ── Object Pool (avoid GC spikes) ──
class ObjectPool {
  constructor(factory, reset, initialSize = 20) {
    this._factory = factory;
    this._reset = reset;
    this._pool = [];
    for (let i = 0; i < initialSize; i++) this._pool.push(factory());
  }
  acquire() { return this._pool.length ? this._pool.pop() : this._factory(); }
  release(obj) { this._reset(obj); this._pool.push(obj); }
  get size() { return this._pool.length; }
}

// ── State Machine (clean game flow) ──
class StateMachine {
  constructor(owner) { this.owner = owner; this._states = {}; this._current = null; }
  add(name, state) { this._states[name] = state; return this; }
  set(name, ...args) {
    if (this._current && this._states[this._current].exit) this._states[this._current].exit.call(this.owner);
    this._current = name;
    if (this._states[name].enter) this._states[name].enter.call(this.owner, ...args);
  }
  update(dt) { if (this._current && this._states[this._current].update) this._states[this._current].update.call(this.owner, dt); }
  get current() { return this._current; }
}

// ── Observer / Event Bus (decoupled communication) ──
class EventBus {
  constructor() { this._listeners = {}; }
  on(event, fn, ctx) { (this._listeners[event] = this._listeners[event] || []).push({ fn, ctx }); return this; }
  off(event, fn) {
    if (!this._listeners[event]) return;
    this._listeners[event] = this._listeners[event].filter(l => l.fn !== fn);
  }
  emit(event, ...args) {
    if (!this._listeners[event]) return;
    for (const l of this._listeners[event]) l.fn.call(l.ctx, ...args);
  }
}

// ── Command (undo/redo, replay) ──
class CommandQueue {
  constructor(maxSize = 50) { this._undo = []; this._redo = []; this._max = maxSize; }
  execute(cmd) {
    cmd.execute();
    this._undo.push(cmd);
    if (this._undo.length > this._max) this._undo.shift();
    this._redo = [];
  }
  undo() {
    const cmd = this._undo.pop();
    if (!cmd) return false;
    cmd.undo(); this._redo.push(cmd); return true;
  }
  redo() {
    const cmd = this._redo.pop();
    if (!cmd) return false;
    cmd.execute(); this._undo.push(cmd); return true;
  }
}

// ── Timer (game loop friendly, no setTimeout spam) ──
class Timer {
  constructor() { this._timers = []; }
  after(delay, callback, repeat = false) {
    this._timers.push({ delay, elapsed: 0, callback, repeat, done: false });
  }
  update(dt) {
    for (const t of this._timers) {
      if (t.done) continue;
      t.elapsed += dt;
      if (t.elapsed >= t.delay) { t.callback(); if (t.repeat) t.elapsed = 0; else t.done = true; }
    }
    this._timers = this._timers.filter(t => !t.done);
  }
}

// ── Tween Engine (lightweight, no dependencies) ──
class Tween {
  constructor(target) { this._target = target; this._tweens = []; }
  to(props, duration, easing = 'easeOut', delay = 0) {
    this._tweens.push({ props, duration, elapsed: -delay, easing, startProps: {} });
    for (const k of Object.keys(props)) this._tweens[this._tweens.length-1].startProps[k] = this._target[k];
    return this;
  }
  update(dt) {
    for (const tw of this._tweens) {
      tw.elapsed += dt;
      if (tw.elapsed < 0) continue;
      const t = Math.min(1, tw.elapsed / tw.duration);
      const e = Tween.Easing[tw.easing] ? Tween.Easing[tw.easing](t) : t;
      for (const [k, v] of Object.entries(tw.props)) {
        this._target[k] = tw.startProps[k] + (v - tw.startProps[k]) * e;
      }
    }
    this._tweens = this._tweens.filter(tw => tw.elapsed < tw.duration);
  }
  get done() { return this._tweens.length === 0; }
}
Tween.Easing = {
  linear: t => t,
  easeIn: t => t * t,
  easeOut: t => t * (2 - t),
  easeInOut: t => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t,
  bounce: t => { if (t < 1/2.75) return 7.5625*t*t; if (t < 2/2.75) { t-=1.5/2.75; return 7.5625*t*t+0.75; } if (t < 2.5/2.75) { t-=2.25/2.75; return 7.5625*t*t+0.9375; } t-=2.625/2.75; return 7.5625*t*t+0.984375; },
  elastic: t => t===0||t===1?t:Math.pow(2,-10*t)*Math.sin((t-0.075)*(2*Math.PI)/0.3)+1
};

// ── Behavior Tree (lightweight, inspired by MistreevousSharp) ──
class BehaviorTree {
  constructor(root) { this._root = root; }
  tick(agent) { return this._root.tick(agent); }
}
// BT Nodes
class BTSequence {
  constructor(children) { this.children = children; }
  tick(agent) { for (const c of this.children) { if (c.tick(agent) === 'FAILURE') return 'FAILURE'; } return 'SUCCESS'; }
}
class BTSelector {
  constructor(children) { this.children = children; }
  tick(agent) { for (const c of this.children) { if (c.tick(agent) === 'SUCCESS') return 'SUCCESS'; } return 'FAILURE'; }
}
class BTCondition {
  constructor(cond) { this.cond = cond; }
  tick(agent) { return this.cond(agent) ? 'SUCCESS' : 'FAILURE'; }
}
class BTAction {
  constructor(action) { this.action = action; }
  tick(agent) { this.action(agent); return 'SUCCESS'; }
}

export { ObjectPool, StateMachine, EventBus, CommandQueue, Timer, Tween, BehaviorTree, BTSequence, BTSelector, BTCondition, BTAction };
