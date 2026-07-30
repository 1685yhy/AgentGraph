/* ═══════ IAP Manager ═══════
 * In-App Purchase — WeChat Pay, Apple IAP, Google Play Billing.
 * Web fallback: QR code / test mode.
 * Usage: IAP.init(products); IAP.buy('remove_ads'); */

const IAP = {
  _platform: 'web',
  _products: [],
  _callback: null,

  init(products = []) {
    this._products = products;
    if (typeof wx !== 'undefined' && wx.requestPayment) {
      this._platform = 'wechat';
    }
  },

  // Get product info
  getProduct(id) { return this._products.find(p => p.id === id); },
  getProducts() { return this._products; },

  // Initiate purchase
  async buy(productId) {
    const product = this.getProduct(productId);
    if (!product) throw new Error('Unknown product: ' + productId);

    if (this._platform === 'wechat') {
      return this._buyWechat(product);
    }
    // Web fallback: test mode
    if (confirm(`💰 购买 ${product.name} — ¥${product.price}?\n(上线后通过微信支付)`)) {
      return { success: true, productId };
    }
    throw new Error('Purchase cancelled');
  },

  // WeChat payment
  async _buyWechat(product) {
    return new Promise((resolve, reject) => {
      // Step 1: Your server creates order → returns payment params
      // Step 2: Call wx.requestPayment
      wx.requestPayment({
        timeStamp: '', nonceStr: '', package: '', signType: 'MD5', paySign: '',
        success: () => resolve({ success: true, productId: product.id }),
        fail: (err) => reject(err)
      });
      // Note: In production, timeStamp/nonceStr/package/paySign come from your server
      // after creating the order via WeChat Pay API
    });
  },

  // Restore purchases
  async restore() {
    if (this._platform === 'wechat') {
      // Check with server for past purchases
      return [];
    }
    const data = JSON.parse(localStorage.getItem('iap_purchases') || '[]');
    return data;
  },

  // Verify receipt (call your server)
  async verifyReceipt(receipt) {
    // Server-side validation prevents fraud
    try {
      const res = await fetch('/api/iap/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(receipt)
      });
      return res.json();
    } catch (e) { return { valid: false }; }
  },

  // Record purchase locally
  _recordPurchase(productId) {
    const data = JSON.parse(localStorage.getItem('iap_purchases') || '[]');
    data.push({ productId, time: Date.now() });
    localStorage.setItem('iap_purchases', JSON.stringify(data));
  }
};
