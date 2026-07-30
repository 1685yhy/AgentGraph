/* ═══════ Leaderboard Module (Leancloud) ═══════
 * Usage: LB.init(appId, appKey); LB.submit(name, score); LB.getTop(10)
 * Falls back to localStorage if Leancloud not configured */

const LB = {
  _inited: false, _localKey: 'lb_local_scores',

  init(appId, appKey) {
    if (appId && appKey && typeof AV !== 'undefined') {
      try {
        AV.init({ appId, appKey, serverURL: 'https://' + appId.slice(0, 8) + '.api.lncldglobal.com' });
        this._inited = true;
      } catch (e) { console.warn('Leancloud init failed, using local'); }
    }
  },

  async submit(name, score, extra = {}) {
    if (this._inited) {
      try {
        const Score = AV.Object.extend('Score');
        const s = new Score();
        await s.save({ name, score, province: extra.province || '', timestamp: new Date() });
        return true;
      } catch (e) { /* fallback */ }
    }
    // localStorage fallback
    const data = JSON.parse(localStorage.getItem(this._localKey) || '[]');
    data.push({ name, score, province: extra.province || '', date: new Date().toISOString() });
    data.sort((a, b) => b.score - a.score);
    localStorage.setItem(this._localKey, JSON.stringify(data.slice(0, 100)));
    return true;
  },

  async getTop(limit = 10) {
    if (this._inited) {
      try {
        const q = new AV.Query('Score');
        q.descending('score'); q.limit(limit);
        const results = await q.find();
        return results.map(r => r.toJSON());
      } catch (e) { /* fallback */ }
    }
    const data = JSON.parse(localStorage.getItem(this._localKey) || '[]');
    return data.slice(0, limit);
  },

  async getRank(score) {
    if (this._inited) {
      try {
        const q = new AV.Query('Score'); q.greaterThan('score', score);
        return await q.count() + 1;
      } catch (e) { return 1; }
    }
    const data = JSON.parse(localStorage.getItem(this._localKey) || '[]');
    return data.filter(s => s.score > score).length + 1;
  }
};
