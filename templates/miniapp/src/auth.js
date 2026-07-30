/* ═══════ 微信小程序 Auth Module ═══════
 * wx.login → code2session → JWT → 自动刷新
 * Usage: Auth.login().then(user => ...) */

const Auth = {
  _token: null,
  _user: null,

  async login() {
    // Step 1: wx.login获取code
    const { code } = await wx.login();
    // Step 2: 后端用code换取openid+JWT
    const res = await wx.request({
      url: 'https://your-api.com/auth/login',
      method: 'POST',
      data: { code }
    });
    this._token = res.data.token;
    this._user = res.data.user;
    wx.setStorageSync('token', this._token);
    return this._user;
  },

  async checkLogin() {
    const token = wx.getStorageSync('token');
    if (!token) return false;
    try {
      const res = await wx.request({
        url: 'https://your-api.com/auth/check',
        header: { Authorization: `Bearer ${token}` }
      });
      this._token = token;
      this._user = res.data.user;
      return true;
    } catch (e) { return false; }
  },

  getUser() { return this._user; },
  getToken() { return this._token; },
  logout() { this._token = null; this._user = null; wx.removeStorageSync('token'); }
};
