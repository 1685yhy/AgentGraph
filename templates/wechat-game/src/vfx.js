/* ═══════ VFX Library ═══════
 * Particle emitter, screen shake, flash, transitions, floating text, trail.
 * Game feel layer — the difference between "functional" and "polished".
 * Zero dependencies. Works with Canvas/Phaser/DOM. */

const VFX = {
  _particles: [],
  _canvas: null,
  _ctx: null,

  // Bind to a canvas for particle rendering
  bind(canvas) { this._canvas = canvas; this._ctx = canvas.getContext('2d'); },

  // ── Particle Emitter ──
  emit(x, y, opts = {}) {
    const count = opts.count || 10;
    const color = opts.color || '#f6c94d';
    const colors = Array.isArray(color) ? color : [color];
    const life = opts.life || 0.8;
    const speed = opts.speed || 3;
    const size = opts.size || 3;
    const gravity = opts.gravity || 0;

    for (let i = 0; i < count; i++) {
      const angle = (Math.PI * 2 * i / count) + (opts.spread ? (Math.random() - 0.5) * opts.spread : 0);
      this._particles.push({
        x, y,
        vx: Math.cos(angle) * speed * (0.5 + Math.random()),
        vy: Math.sin(angle) * speed * (0.5 + Math.random()) - 2,
        life, maxLife: life,
        size: size * (0.5 + Math.random()),
        color: colors[Math.floor(Math.random() * colors.length)],
        gravity
      });
    }
  },

  // ── Screen Shake ──
  shake(target, intensity = 6, duration = 300) {
    if (target._shakeTimer) return;
    const origX = target.x || 0, origY = target.y || 0;
    const startTime = Date.now();
    target._shakeTimer = setInterval(() => {
      const elapsed = Date.now() - startTime;
      if (elapsed >= duration) {
        if (target.x !== undefined) target.x = origX; // Phaser
        if (target.y !== undefined) target.y = origY;
        clearInterval(target._shakeTimer);
        target._shakeTimer = null;
        return;
      }
      const decay = 1 - elapsed / duration;
      const dx = (Math.random() - 0.5) * intensity * decay * 2;
      const dy = (Math.random() - 0.5) * intensity * decay * 2;
      if (target.x !== undefined) target.x = origX + dx;
      if (target.y !== undefined) target.y = origY + dy;
      if (target.camera) target.camera.setScroll(-dx, -dy); // alternative: shift camera
    }, 16);
  },

  // ── Screen Flash ──
  flash(color = '#ffffff', duration = 150) {
    const el = document.createElement('div');
    el.style.cssText = `position:fixed;top:0;left:0;width:100%;height:100%;background:${color};z-index:9999;pointer-events:none;animation:vfxFlash ${duration}ms ease-out forwards;`;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), duration + 50);
    if (!this._flashStyle) {
      const s = document.createElement('style'); s.textContent = '@keyframes vfxFlash{from{opacity:0.6}to{opacity:0}}';
      document.head.appendChild(s); this._flashStyle = true;
    }
  },

  // ── Floating Text (damage numbers, score popups) ──
  floatText(x, y, text, opts = {}) {
    const color = opts.color || '#f6c94d';
    const size = opts.size || 20;
    const duration = opts.duration || 1000;
    const el = document.createElement('div');
    el.style.cssText = `position:fixed;left:${x}px;top:${y}px;font-family:-apple-system,sans-serif;font-size:${size}px;font-weight:800;color:${color};pointer-events:none;text-shadow:0 2px 8px rgba(0,0,0,0.5);animation:vfxFloat ${duration}ms ease-out forwards;z-index:999;`;
    el.textContent = text;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), duration + 50);
    if (!this._floatStyle) {
      const s = document.createElement('style'); s.textContent = '@keyframes vfxFloat{0%{opacity:1;transform:translateY(0) scale(0.8)}30%{opacity:1;transform:translateY(-20px) scale(1.2)}100%{opacity:0;transform:translateY(-60px) scale(1)}}';
      document.head.appendChild(s); this._floatStyle = true;
    }
    return el;
  },

  // ── Trail Effect ──
  trail(ctx, x, y, prevX, prevY, color, width = 4, opacity = 0.5) {
    ctx.save();
    ctx.globalAlpha = opacity;
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(prevX, prevY); ctx.lineTo(x, y); ctx.stroke();
    ctx.restore();
  },

  // ── Update (call in game loop) ──
  update(dt) {
    if (!this._ctx) return;
    for (let i = this._particles.length - 1; i >= 0; i--) {
      const p = this._particles[i];
      p.x += p.vx; p.y += p.vy; p.vy += p.gravity;
      p.life -= dt;
      if (p.life <= 0) { this._particles.splice(i, 1); continue; }
    }
  },

  // ── Draw (call in render loop) ──
  draw(ctx) {
    for (const p of this._particles) {
      const alpha = p.life / p.maxLife;
      ctx.globalAlpha = alpha;
      ctx.fillStyle = p.color;
      ctx.beginPath(); ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2); ctx.fill();
    }
    ctx.globalAlpha = 1;
  },

  // ── Pre-built effects ──
  celebrate(x, y) { this.emit(x, y, { count: 16, color: ['#f6c94d','#f85149','#58a6ff','#3fb950','#a78bfa'], life: 1.2, speed: 5, gravity: 100 }); },
  explode(x, y) { this.emit(x, y, { count: 12, color: ['#f85149','#d29922','#ff7b72'], life: 0.6, speed: 6, spread: Math.PI * 2 }); },
  spark(x, y) { this.emit(x, y, { count: 6, color: '#f6c94d', life: 0.4, speed: 4, spread: 1.5 }); },
  ripple(x, y, count = 3) { for (let i = 0; i < count; i++) setTimeout(() => this.emit(x, y, { count: 8, color: '#58a6ff33', life: 0.5, speed: 2 }), i * 100); },
};
