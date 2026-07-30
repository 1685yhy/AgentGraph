/* ═══════ Tutorial System ═══════
 * Step-by-step guided tutorial with highlight, skip, and progress tracking.
 * 羊了个羊问题: 用户不知道怎么玩 → 流失.
 * Solution: 交互式引导, 每步一个清晰动作, 允许跳过. */

class TutorialSystem {
  constructor(canvas) {
    this._canvas = canvas;
    this._steps = [];
    this._currentStep = -1;
    this._active = false;
    this._overlay = null;
    this._hand = null;
    this._text = null;
  }

  // Define tutorial steps
  // Each step: { target: {x,y,w,h} or null(center), text: "提示文字", action: fn, autoAdvance: bool }
  defineSteps(steps) {
    this._steps = steps;
  }

  // Start tutorial
  start() {
    if (this._steps.length === 0) return;
    this._active = true;
    this._createOverlay();
    this._currentStep = -1;
    this._nextStep();
  }

  // Skip tutorial
  skip() {
    this._active = false;
    this._destroyOverlay();
    localStorage.setItem('tutorial_done', '1');
  }

  // Mark a specific action as done (called from game code)
  completeAction(name) {
    if (!this._active) return;
    const step = this._steps[this._currentStep];
    if (step && step.actionName === name) this._nextStep();
  }

  get active() { return this._active; }
  get isDone() { return localStorage.getItem('tutorial_done') === '1'; }

  // Internal
  _createOverlay() {
    // Semi-transparent overlay
    this._overlay = document.createElement('div');
    this._overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;z-index:999;pointer-events:none;';
    document.body.appendChild(this._overlay);

    // Highlight circle (cut-out effect via box-shadow)
    this._highlight = document.createElement('div');
    this._highlight.style.cssText = 'position:absolute;border:3px solid #f6c94d;border-radius:50%;box-shadow:0 0 0 9999px rgba(0,0,0,0.6);pointer-events:none;transition:all 0.3s ease-out;';
    this._overlay.appendChild(this._highlight);

    // Hand pointer
    this._hand = document.createElement('div');
    this._hand.style.cssText = 'position:absolute;font-size:32px;pointer-events:none;animation:tutBounce 0.8s ease-in-out infinite;z-index:1000;';
    this._hand.textContent = '👆';
    this._overlay.appendChild(this._hand);

    // Text bubble
    this._text = document.createElement('div');
    this._text.style.cssText = 'position:absolute;background:#1a1a2e;color:#fff;padding:12px 18px;border-radius:12px;font-family:-apple-system,sans-serif;font-size:14px;max-width:250px;text-align:center;pointer-events:none;z-index:1000;border:1px solid rgba(255,255,255,0.1);box-shadow:0 8px 32px rgba(0,0,0,0.5);';
    this._overlay.appendChild(this._text);

    // Skip button
    this._skipBtn = document.createElement('button');
    this._skipBtn.style.cssText = 'position:fixed;top:20px;right:20px;z-index:1001;background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.2);color:#fff;padding:8px 16px;border-radius:8px;font-size:12px;cursor:pointer;pointer-events:auto;';
    this._skipBtn.textContent = '跳过';
    this._skipBtn.onclick = () => this.skip();
    this._overlay.appendChild(this._skipBtn);

    // Animation style
    const style = document.createElement('style');
    style.textContent = '@keyframes tutBounce{0%,100%{transform:translateY(0)}50%{transform:translateY(-10px)}}';
    document.head.appendChild(style);
    this._animStyle = style;
  }

  _nextStep() {
    this._currentStep++;
    if (this._currentStep >= this._steps.length) { this.skip(); return; }
    const step = this._steps[this._currentStep];

    if (step.target) {
      const r = this._canvas.getBoundingClientRect();
      const cx = r.left + step.target.x + step.target.w / 2;
      const cy = r.top + step.target.y + step.target.h / 2;
      const size = Math.max(step.target.w, step.target.h) + 20;

      this._highlight.style.left = (cx - size/2) + 'px';
      this._highlight.style.top = (cy - size/2) + 'px';
      this._highlight.style.width = size + 'px';
      this._highlight.style.height = size + 'px';
      this._highlight.style.opacity = '1';

      this._hand.style.left = (cx - 16) + 'px';
      this._hand.style.top = (cy - 50) + 'px';
    } else {
      this._highlight.style.opacity = '0';
      this._hand.style.left = '50%';
      this._hand.style.top = '55%';
    }

    this._text.textContent = step.text;
    this._text.style.left = '50%';
    this._text.style.top = step.target ? (this._hand.offsetTop + 60) + 'px' : '40%';
    this._text.style.transform = 'translate(-50%,0)';

    // Click to advance (if not auto-advance)
    if (!step.autoAdvance) {
      const handler = () => {
        if (step.action) step.action();
        this._nextStep();
        this._canvas.removeEventListener('click', handler);
        this._canvas.removeEventListener('touchstart', handler);
      };
      setTimeout(() => {
        this._canvas.addEventListener('click', handler);
        this._canvas.addEventListener('touchstart', handler);
      }, 100);
    }
  }

  _destroyOverlay() {
    if (this._overlay) { this._overlay.remove(); this._overlay = null; }
    if (this._animStyle) { this._animStyle.remove(); this._animStyle = null; }
    this._highlight = null; this._hand = null; this._text = null; this._skipBtn = null;
  }

  // Mark tutorial as done for this user
  markDone() { localStorage.setItem('tutorial_done', '1'); }
  reset() { localStorage.removeItem('tutorial_done'); }
}
