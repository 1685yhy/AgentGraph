/* ═══════ Performance Monitor ═══════
 * FPS counter, memory tracking, load time measurement.
 * In-game HUD overlay for development.
 * Zero dependencies. */

class PerfMonitor {
  constructor() {
    this._fps = 0;
    this._frames = 0;
    this._lastFpsTime = performance.now();
    this._minFps = Infinity;
    this._maxFps = 0;
    this._fpsHistory = [];
    this._loadStart = performance.now();
    this._markers = {};
    this._hud = null;
    this._visible = false;
    this._jankCount = 0;
    this._lastFrameTime = 0;
  }

  // Mark a timing point (e.g., 'assets-loaded', 'game-ready')
  mark(name) {
    this._markers[name] = performance.now();
  }

  // Get time since load start or since a marker
  elapsed(since) {
    const start = since ? (this._markers[since] || this._loadStart) : this._loadStart;
    return Math.round(performance.now() - start);
  }

  // Called every frame
  frame(dt) {
    this._frames++;
    // Jank detection: frame > 2x expected (for 60fps: >33ms)
    if (dt > 33 && this._lastFrameTime > 0) this._jankCount++;

    const now = performance.now();
    if (now - this._lastFpsTime >= 1000) {
      this._fps = Math.round(this._frames * 1000 / (now - this._lastFpsTime));
      this._minFps = Math.min(this._minFps, this._fps);
      this._maxFps = Math.max(this._maxFps, this._fps);
      this._fpsHistory.push(this._fps);
      if (this._fpsHistory.length > 60) this._fpsHistory.shift(); // keep 60s
      this._frames = 0;
      this._lastFpsTime = now;
      if (this._hud) this._updateHud();
    }
    this._lastFrameTime = dt;
  }

  // Get current stats
  getStats() {
    let memory = null;
    if (performance.memory) {
      memory = {
        used: Math.round(performance.memory.usedJSHeapSize / 1048576),
        total: Math.round(performance.memory.totalJSHeapSize / 1048576),
        limit: Math.round(performance.memory.jsHeapSizeLimit / 1048576)
      };
    }
    return {
      fps: this._fps,
      avgFps: this._fpsHistory.length ? Math.round(this._fpsHistory.reduce((a,b)=>a+b,0) / this._fpsHistory.length) : 0,
      minFps: this._minFps,
      maxFps: this._maxFps,
      jank: this._jankCount,
      loadTime: this.elapsed(),
      memory,
      markers: this._markers
    };
  }

  // Show FPS HUD (development only)
  show() {
    if (this._hud) return;
    this._hud = document.createElement('div');
    this._hud.style.cssText = 'position:fixed;top:5px;left:5px;z-index:9999;background:rgba(0,0,0,0.7);color:#0f0;font:11px monospace;padding:4px 8px;border-radius:4px;pointer-events:none;line-height:1.4';
    document.body.appendChild(this._hud);
    this._visible = true;
  }

  hide() {
    if (this._hud) { this._hud.remove(); this._hud = null; }
    this._visible = false;
  }

  _updateHud() {
    if (!this._hud) return;
    const s = this.getStats();
    const color = s.fps >= 55 ? '#0f0' : s.fps >= 30 ? '#ff0' : '#f00';
    this._hud.style.color = color;
    this._hud.innerHTML = `FPS:${s.fps} | MIN:${s.minFps} | JANK:${s.jank}` +
      (s.memory ? `<br>MEM:${s.memory.used}/${s.memory.total}MB` : '');
  }

  // Log report to console
  report() {
    const s = this.getStats();
    console.log('=== Performance Report ===');
    console.log(`Avg FPS: ${s.avgFps} (min: ${s.minFps}, max: ${s.maxFps})`);
    console.log(`Jank frames: ${s.jank}`);
    console.log(`Load time: ${s.loadTime}ms`);
    if (s.memory) console.log(`Memory: ${s.memory.used}MB / ${s.memory.total}MB (limit: ${s.memory.limit}MB)`);
  }
}
