/* ═══════ Analytics ═══════
 * Event tracking, funnel analysis, session management.
 * Pluggable backends: Leancloud, Google Analytics, custom endpoint.
 * Privacy-first: no PII, opt-out support. */

class Analytics {
  constructor(gameId = 'default') {
    this._gameId = gameId;
    this._sessionId = this._genId();
    this._sessionStart = Date.now();
    this._events = [];
    this._funnels = {};
    this._endpoint = null;
    this._flushInterval = null;
    this._userId = null;
    this._enabled = true;
  }

  // Set reporting endpoint
  setEndpoint(url) { this._endpoint = url; }
  setUserId(uid) { this._userId = uid; }
  setEnabled(v) { this._enabled = v; }

  // Track an event
  track(event, properties = {}) {
    if (!this._enabled) return;
    const evt = {
      event, properties,
      sessionId: this._sessionId,
      timestamp: Date.now(),
      gameId: this._gameId,
      userId: this._userId,
      screenW: window.innerWidth, screenH: window.innerHeight
    };
    this._events.push(evt);
    // Auto-flush when buffer reaches threshold
    if (this._events.length >= 20) this.flush();
  }

  // Start a funnel
  funnelStart(name) {
    this._funnels[name] = { start: Date.now(), steps: [] };
    this.track('funnel_start', { funnel: name });
  }

  // Record a funnel step
  funnelStep(name, step) {
    if (!this._funnels[name]) return;
    this._funnels[name].steps.push({ step, time: Date.now() });
    this.track('funnel_step', { funnel: name, step });
  }

  // Complete a funnel
  funnelEnd(name, result = 'complete') {
    if (!this._funnels[name]) return;
    const f = this._funnels[name];
    const duration = Date.now() - f.start;
    this.track('funnel_end', { funnel: name, result, duration, steps: f.steps.length });
    delete this._funnels[name];
  }

  // Session info
  getSessionInfo() {
    return {
      sessionId: this._sessionId,
      duration: Math.round((Date.now() - this._sessionStart) / 1000),
      eventCount: this._events.length
    };
  }

  // Flush events to backend
  async flush() {
    if (!this._events.length) return;
    const batch = this._events.splice(0);
    if (this._endpoint) {
      try {
        await fetch(this._endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ events: batch, session: this.getSessionInfo() })
        });
      } catch (e) {}
    }
    // Also save to Leancloud if available
    if (typeof AV !== 'undefined') {
      try {
        const AnalyticEvent = AV.Object.extend('AnalyticEvent');
        for (const e of batch.slice(0, 10)) { // limit cloud writes
          const obj = new AnalyticEvent();
          await obj.save(e);
        }
      } catch (e) {}
    }
  }

  // Enable auto-flush
  enableAutoFlush(intervalMs = 30000) {
    this._flushInterval = setInterval(() => this.flush(), intervalMs);
    window.addEventListener('beforeunload', () => this.flush());
  }

  // Common game events
  gameStart() { this.track('game_start'); }
  gameOver(score, reason) { this.track('game_over', { score, reason }); }
  adWatched(type) { this.track('ad_watched', { type }); }
  purchase(item, price) { this.track('purchase', { item, price }); }
  share(method) { this.track('share', { method }); }
  levelComplete(level, score, time) { this.track('level_complete', { level, score, time }); }

  // Privacy: opt out
  optOut() { this._enabled = false; this._events = []; }

  _genId() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 8); }
}
