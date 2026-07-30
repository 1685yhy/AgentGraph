/* ═══════ UI Kit ═══════
 * Game UI components — Button, Modal, Toast, HealthBar, Spinner, Badge, Toggle.
 * Designed for Phaser but works standalone with DOM overlay.
 * Inspired by Unity UI Toolkit Design System (github.com/sinanata/unity-ui-toolkit-design-system)
 * Zero dependencies. */

const UI = {
  _container: null,
  _toasts: [],

  // Initialize UI layer (creates overlay div)
  init(zIndex = 100) {
    this._container = document.createElement('div');
    this._container.id = 'ui-layer';
    this._container.style.cssText = `position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:${zIndex};`;
    document.body.appendChild(this._container);
    // Toast container
    this._toastContainer = document.createElement('div');
    this._toastContainer.style.cssText = 'position:fixed;top:60px;left:50%;transform:translateX(-50%);z-index:1001;display:flex;flex-direction:column;gap:8px;pointer-events:none;';
    document.body.appendChild(this._toastContainer);
  },

  // ── Toast ──
  toast(text, type = 'info', duration = 2000) {
    const el = document.createElement('div');
    const colors = { info: '#58a6ff', success: '#3fb950', warn: '#d29922', error: '#f85149' };
    el.style.cssText = `
      background:#1a1a2e;color:#fff;padding:10px 20px;border-radius:10px;font-family:-apple-system,sans-serif;
      font-size:14px;text-align:center;pointer-events:auto;border-left:3px solid ${colors[type]||colors.info};
      box-shadow:0 4px 16px rgba(0,0,0,0.4);animation:uiSlideIn 0.3s ease-out,uiFadeOut 0.3s ${duration-300}ms ease-out forwards;
      max-width:300px;
    `;
    el.textContent = text;
    this._toastContainer.appendChild(el);
    setTimeout(() => el.remove(), duration);
  },

  // ── Modal ──
  modal({ title, body, buttons = [], onClose }) {
    const bg = document.createElement('div');
    bg.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.8);z-index:1000;display:flex;justify-content:center;align-items:center;pointer-events:auto;animation:uiFadeIn 0.2s ease-out;';
    const panel = document.createElement('div');
    panel.style.cssText = 'background:#1a1a2e;border-radius:16px;padding:24px;max-width:320px;width:90%;border:1px solid rgba(255,255,255,0.08);box-shadow:0 20px 60px rgba(0,0,0,0.5);animation:uiScaleIn 0.3s ease-out;';
    if (title) { const h2 = document.createElement('h2'); h2.style.cssText = 'font-family:-apple-system,sans-serif;font-size:20px;font-weight:800;color:#fff;margin:0 0 8px;text-align:center;'; h2.textContent = title; panel.appendChild(h2); }
    if (body) { const p = document.createElement('p'); p.style.cssText = 'font-family:-apple-system,sans-serif;font-size:14px;color:#8b949e;margin:0 0 16px;text-align:center;line-height:1.5;'; p.innerHTML = body; panel.appendChild(p); }
    buttons.forEach(b => {
      const btn = document.createElement('button');
      const isPrimary = b.primary !== false;
      btn.style.cssText = `display:block;width:100%;padding:14px;margin:6px 0;border-radius:12px;border:none;font-family:-apple-system,sans-serif;font-size:15px;font-weight:700;cursor:pointer;color:${isPrimary?'#000':'#fff'};background:${isPrimary?'#f6c94d':'rgba(255,255,255,0.08)'};transition:transform 0.15s;pointer-events:auto;`;
      btn.textContent = b.label;
      btn.onclick = () => { bg.remove(); if (b.onClick) b.onClick(); };
      panel.appendChild(btn);
    });
    bg.appendChild(panel);
    bg.onclick = (e) => { if (e.target === bg) { bg.remove(); if (onClose) onClose(); } };
    document.body.appendChild(bg);
    return { close: () => bg.remove() };
  },

  // ── Loading Spinner ──
  spinner(text = '加载中...') {
    const el = document.createElement('div');
    el.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:1000;text-align:center;pointer-events:auto;';
    el.innerHTML = `<div style="width:40px;height:40px;border:3px solid rgba(255,255,255,0.1);border-top-color:#58a6ff;border-radius:50%;animation:uiSpin 0.8s linear infinite;margin:0 auto 12px;"></div><div style="font-family:-apple-system,sans-serif;font-size:14px;color:#8b949e;">${text}</div>`;
    document.body.appendChild(el);
    return { close: () => el.remove() };
  },

  // ── Health / Progress Bar ──
  bar({ x, y, width, height, value, max, color, bgColor, parent }) {
    const container = parent || document.body;
    const bg = document.createElement('div');
    bg.style.cssText = `position:absolute;left:${x}px;top:${y}px;width:${width}px;height:${height}px;background:${bgColor||'rgba(255,255,255,0.1)'};border-radius:${height/2}px;overflow:hidden;`;
    const fill = document.createElement('div');
    const pct = Math.min(100, Math.round(value/max*100));
    fill.style.cssText = `width:${pct}%;height:100%;background:${color||'#3fb950'};border-radius:${height/2}px;transition:width 0.3s ease-out;`;
    bg.appendChild(fill);
    container.appendChild(bg);
    return {
      update: (v) => { const p = Math.min(100, Math.round(v/max*100)); fill.style.width = p + '%'; },
      remove: () => bg.remove()
    };
  },

  // ── Badge ──
  badge(parent, text, color = '#f85149') {
    const el = document.createElement('div');
    el.style.cssText = `position:absolute;top:-6px;right:-6px;background:${color};color:#fff;font-family:-apple-system,sans-serif;font-size:10px;font-weight:700;min-width:18px;height:18px;border-radius:9px;display:flex;align-items:center;justify-content:center;padding:0 5px;pointer-events:none;`;
    el.textContent = text;
    parent.style.position = 'relative';
    parent.appendChild(el);
    return { update: (t) => { el.textContent = t; }, remove: () => el.remove() };
  },

  // ── Toggle ──
  toggle(parent, checked = false, onChange) {
    const el = document.createElement('div');
    el.style.cssText = `width:48px;height:28px;border-radius:14px;background:${checked?'#3fb950':'#30363d'};cursor:pointer;transition:background 0.2s;position:relative;pointer-events:auto;`;
    const knob = document.createElement('div');
    knob.style.cssText = `position:absolute;top:2px;left:${checked?22:2}px;width:24px;height:24px;border-radius:50%;background:#fff;transition:left 0.2s;box-shadow:0 1px 3px rgba(0,0,0,0.3);`;
    el.appendChild(knob);
    el.onclick = () => {
      checked = !checked;
      el.style.background = checked ? '#3fb950' : '#30363d';
      knob.style.left = checked ? '22px' : '2px';
      if (onChange) onChange(checked);
    };
    if (parent) parent.appendChild(el);
    return el;
  },

  // ── CSS Animations (inject once) ──
  _stylesInjected: false,
  _injectStyles() {
    if (this._stylesInjected) return;
    const s = document.createElement('style');
    s.textContent = '@keyframes uiSlideIn{from{transform:translateY(-10px);opacity:0}}@keyframes uiFadeOut{to{opacity:0}}@keyframes uiFadeIn{from{opacity:0}}@keyframes uiScaleIn{from{transform:scale(0.9);opacity:0}}@keyframes uiSpin{to{transform:rotate(360deg)}}';
    document.head.appendChild(s);
    this._stylesInjected = true;
  }
};
UI._injectStyles();
