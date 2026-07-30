/* ═══════ Social Challenge System ═══════
 * Friend challenge codes, weekly tournaments, invite tracking, gift system.
 * Drives viral growth through social mechanics.
 * 羊了个羊核心: 省份排名+好友比拼 → 疯狂传播 */

const Social = {
  _userId: null,
  _userName: null,
  _province: null,

  init(userName, province) {
    this._userId = this._loadId();
    this._userName = userName || '玩家' + this._userId.slice(0, 4);
    this._province = province || '';
  },

  // ── Challenge Codes ──
  // Generate a short code that friends can use to join a challenge
  createChallenge(score, gameMode = 'default') {
    const code = this._encode({ u: this._userId, n: this._userName, s: score, p: this._province, m: gameMode, t: Date.now() });
    return { code, text: `我在${gameMode}模式得了${score}分！挑战码: ${code}，来超越我吧！` };
  },

  // Decode a challenge from a friend
  decodeChallenge(code) {
    try { return this._decode(code); } catch (e) { return null; }
  },

  // ── Weekly Tournament ──
  getWeekNumber() {
    const now = new Date(); const start = new Date(now.getFullYear(), 0, 1);
    return Math.ceil(((now - start) / 86400000 + start.getDay() + 1) / 7);
  },

  getTournamentKey() { return `tournament_${this.getWeekNumber()}`; },

  // Submit score to weekly tournament
  submitTournament(score) {
    const key = this.getTournamentKey();
    const data = JSON.parse(localStorage.getItem(key) || '{}');
    const prev = data[this._userId];
    if (!prev || score > prev.score) {
      data[this._userId] = { name: this._userName, score, province: this._province, time: Date.now() };
      localStorage.setItem(key, JSON.stringify(data));
    }
    return this.getTournamentRank(data);
  },

  // Get tournament rankings
  getTournamentRank(data = null) {
    const entries = data || JSON.parse(localStorage.getItem(this.getTournamentKey()) || '{}');
    const sorted = Object.values(entries).sort((a, b) => b.score - a.score);
    const myRank = sorted.findIndex(e => e.time === entries[this._userId]?.time) + 1;
    return {
      top: sorted.slice(0, 10),
      myRank: myRank || '-',
      total: sorted.length,
      myScore: entries[this._userId]?.score || 0
    };
  },

  // ── Province Ranking ──
  getProvinceRankings() {
    const key = this.getTournamentKey();
    const data = JSON.parse(localStorage.getItem(key) || '{}');
    const provinces = {};
    for (const entry of Object.values(data)) {
      const p = entry.province || '其他';
      provinces[p] = Math.max(provinces[p] || 0, entry.score);
    }
    return Object.entries(provinces)
      .map(([name, score]) => ({ name, score }))
      .sort((a, b) => b.score - a.score);
  },

  // ── Daily Challenge ──
  getDailySeed() {
    return Math.floor(Date.now() / 86400000);
  },

  getDailyKey() { return `daily_${this.getDailySeed()}`; },

  submitDaily(score) {
    const key = this.getDailyKey();
    const data = JSON.parse(localStorage.getItem(key) || '{}');
    if (!data[this._userId] || score > data[this._userId].score) {
      data[this._userId] = { name: this._userName, score, province: this._province };
      localStorage.setItem(key, JSON.stringify(data));
    }
    return this.getDailyRank(data);
  },

  getDailyRank(data = null) {
    const entries = data || JSON.parse(localStorage.getItem(this.getDailyKey()) || '{}');
    const sorted = Object.values(entries).sort((a, b) => b.score - a.score);
    const myRank = sorted.findIndex(e => e.score === entries[this._userId]?.score) + 1;
    return { top: sorted.slice(0, 10), myRank: myRank || '-', total: sorted.length };
  },

  // ── Gift System ──
  sendGift(toUserId, giftType = 'life') {
    const key = `gifts_${toUserId}`;
    const gifts = JSON.parse(localStorage.getItem(key) || '[]');
    gifts.push({ from: this._userId, fromName: this._userName, type: giftType, time: Date.now(), claimed: false });
    localStorage.setItem(key, JSON.stringify(gifts));
  },

  getGifts() {
    const key = `gifts_${this._userId}`;
    return JSON.parse(localStorage.getItem(key) || '[]');
  },

  claimGift(giftIndex) {
    const key = `gifts_${this._userId}`;
    const gifts = JSON.parse(localStorage.getItem(key) || '[]');
    if (giftIndex >= gifts.length || gifts[giftIndex].claimed) return null;
    gifts[giftIndex].claimed = true;
    localStorage.setItem(key, JSON.stringify(gifts));
    return gifts[giftIndex];
  },

  // ── Invite Tracking ──
  trackInvite(inviteCode) {
    const invites = JSON.parse(localStorage.getItem('invites') || '[]');
    invites.push({ code: inviteCode, userId: this._userId, time: Date.now() });
    localStorage.setItem('invites', JSON.stringify(invites));
    // Reward the inviter
    const challenge = this.decodeChallenge(inviteCode);
    if (challenge) {
      const rewards = JSON.parse(localStorage.getItem(`rewards_${challenge.u}`) || '[]');
      rewards.push({ type: 'invite_bonus', from: this._userId, time: Date.now() });
      localStorage.setItem(`rewards_${challenge.u}`, JSON.stringify(rewards));
    }
  },

  getRewards() {
    return JSON.parse(localStorage.getItem(`rewards_${this._userId}`) || '[]');
  },

  // ── Share Token ──
  createShareToken(data = {}) {
    const token = btoa(JSON.stringify({ ...data, u: this._userId, t: Date.now() }));
    return token.slice(0, 32); // keep it short for URLs
  },

  // ── Encode/Decode helpers ──
  _encode(obj) {
    return btoa(JSON.stringify(obj)).replace(/[+/=]/g, c => ({'+':'-','/':'_','=':''})[c]).slice(0, 20);
  },
  _decode(str) {
    str = str.replace(/[-_]/g, c => ({'-':'+','_':'/'})[c]);
    return JSON.parse(atob(str));
  },
  _loadId() {
    let id = localStorage.getItem('social_uid');
    if (!id) { id = 'u' + Date.now().toString(36); localStorage.setItem('social_uid', id); }
    return id;
  }
};
