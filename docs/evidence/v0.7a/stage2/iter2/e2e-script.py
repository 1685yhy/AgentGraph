#!/usr/bin/env python3
"""E2E verification of 「无尽矿脉」idle mining game — 修复轮2 (Playwright, headless Chromium).

修复轮1 (F-1..F-10) 全部保留回归；本轮新增：
- B-1 第0天 bug: 北京时间 07:00 首次启动（Asia/Shanghai + 固定时钟）必显「第1天」；
  分享卡同步「第 1 天」；次日 07:00 跨天显示「第2天」（旧代码 UTC 解析会卡在第1天）
- B-2 限时矿脉收尾: 按 DOM 位置定位矿块（splice 后 data-vein-ore 旧下标失配→幽灵项），
  5 块点完立即收尾：条隐藏、veinActive 置空、1.5s 后不空挂、可再次触发新矿脉
- P-1 离线文案: 离线 10h（>8h 封顶）金额按 8h 计算（+7200），文案显示上限提示，
  不再出现「10 小时」与实际金额不一致
- P-2 差一点面板: 带小数金币（138.2）时差额整数化显示（「还差 2 金币」，无小数长尾）
"""
import asyncio, sys, re
from playwright.async_api import async_playwright

URL = "file:///mnt/e/agentguild/docs/evidence/v0.7a/stage2/iter2/deliverable/game/index.html#debug"
SHOT_DIR = "/mnt/e/agentguild/docs/evidence/v0.7a/stage2/iter2"
results = []

async def check(name, cond, detail=""):
    results.append((name, bool(cond), str(detail)))
    print(("PASS " if cond else "FAIL ") + name + (" | " + str(detail) if detail else ""))

def coins_of(text):
    m = re.search(r"\d+", text or "")
    return int(m.group(0)) if m else -1

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 375, "height": 812})
        console_errors = []
        page.on("console", lambda m: console_errors.append("console." + m.type + ": " + m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: console_errors.append("pageerror: " + str(e)))
        dialogs = []
        async def on_dialog(d):
            dialogs.append(d.message)
            try:
                await d.accept()
            except Exception:
                pass
        page.on("dialog", on_dialog)

        def js(expr):
            return page.evaluate(expr)

        async def ore_count():
            return await page.locator('[data-ore]').count()

        async def tap_first_ore(wait=300):
            await page.evaluate("var e=document.querySelector('.ore');if(e){e.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))}")
            await page.wait_for_timeout(wait)

        async def tap_ore(i, wait=300):
            await page.evaluate("var e=document.querySelectorAll('.ore')[" + str(i) + "];if(e){e.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))}")
            await page.wait_for_timeout(wait)

        async def fast_ads():
            await page.evaluate("window.__MINE__ && window.__MINE__.fastAds ? window.__MINE__.fastAds(true) : null")

        async def close_panel_backdrop():
            await page.mouse.click(8, 60)
            await page.wait_for_timeout(250)

        async def rel():
            await page.reload()
            await page.wait_for_timeout(800)
            await fast_ads()

        # ================= 0. fresh state =================
        await page.goto(URL)
        await page.evaluate("localStorage.clear()")
        await rel()
        title = await page.title()
        await check("title 无尽矿脉", "无尽矿脉" in title, title)

        # ================= 0.5 B-1 第0天 bug: 北京时间上午首次启动 =================
        # 东八区 07:00（UTC 仍是前一天 23:00）首次启动：旧代码 new Date('YYYY-MM-DD')
        # 按 UTC 零点解析 → 误算「第0天」；修复后必须显「第1天」，分享卡同步
        ctx_sh = await browser.new_context(timezone_id="Asia/Shanghai")
        page_sh = await ctx_sh.new_page()
        await page_sh.clock.install(time="2026-08-05T07:00:00+08:00")
        await page_sh.goto(URL)
        await page_sh.evaluate("localStorage.clear()")
        await page_sh.reload()
        await page_sh.wait_for_timeout(600)
        day1 = await page_sh.locator("#daychip").text_content()
        await check("B-1 first launch @Beijing 07:00 -> 第1天 (not 第0天)", day1 == "第1天", day1)
        # 引导遮罩(全屏 z-index 200)盖住底栏，先跳过引导再开分享卡
        await page_sh.locator('[data-act="guide-skip"]').click()
        await page_sh.wait_for_timeout(300)
        await page_sh.locator('[data-act="share-card"]').click()
        await page_sh.wait_for_timeout(300)
        sc_days = await page_sh.locator("#sc-days").text_content()
        await check("B-1 share card days sync -> 第 1 天", sc_days == "第 1 天", sc_days)
        # 次日 07:00 跨天：本地日历日差=1 → 第2天（旧代码 UTC 差=0 会卡「第1天」）。
        # 时钟冻结时 setInterval 不触发、无自动存档，手动持久化再重载
        await page_sh.evaluate("localStorage.setItem('wmkuang_save_v1', JSON.stringify(window.__MINE__.state()))")
        await page_sh.clock.set_fixed_time("2026-08-06T07:00:00+08:00")
        await page_sh.reload()
        await page_sh.wait_for_timeout(600)
        day2 = await page_sh.locator("#daychip").text_content()
        await check("B-1 next day 07:00 -> 第2天 (calendar-day diff)", day2 == "第2天", day2)
        await ctx_sh.close()

        # ================= 1. 开局3步引导 + F-5 引导按钮 =================
        step1 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("guide step1 shown", step1 == "1", step1)
        gbtn_h = await js("document.querySelector('#guide .gbtn').getBoundingClientRect().height")
        await check("F-5 guide button >= 44px", gbtn_h >= 44, "%.1f" % gbtn_h)
        await tap_first_ore(wait=120)
        step2 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("guide step2 after first tap", step2 == "2", step2)
        coins = coins_of(await page.locator("#coins").text_content())
        await check("coin +1 after first tap", coins == 1, coins)
        await page.screenshot(path=SHOT_DIR + "/fix-01-guide.png")

        # ================= 2. F-1 第1层: 连挖永不空场(自动补矿) =================
        # 顺序控制：F-1 循环 9 次点击在 XP 20 里程碑之前完成（9+1 XP < 20），
        # 之后攒金币 → 升级钻头完成引导第2步 → 引导第3步点击恰好触发里程碑
        for it in range(3):
            for _ in range(3):
                await tap_first_ore(wait=100)
            cnt0 = await ore_count()
            await check("F-1 layer1 full clear -> grid empty (iter %d)" % it, cnt0 == 0, cnt0)
            await page.wait_for_timeout(1100)
            cnt1 = await ore_count()
            await check("F-1 layer1 auto-refills to 3 (iter %d)" % it, cnt1 == 3, cnt1)
        for r in range(3):
            for _ in range(3):
                await tap_first_ore(wait=100)
            await page.wait_for_timeout(900)
        await tap_first_ore(wait=100)  # 补齐 iter0 少挖的 1 块（引导时网格只剩 2 块），XP 19
        coins = await js("window.__MINE__.state().coins")
        await check("mined >= 10 coins on layer1 (auto-refill)", coins >= 10, coins)
        await page.locator('[data-act="upgrade-drill"]').click()
        await page.wait_for_timeout(300)
        step3 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("guide step3 after drill upgrade", step3 == "3", step3)
        await tap_first_ore(wait=100)  # XP 20 → 里程碑随引导收尾同屏触发
        guide_hidden = not await page.locator("#guide").is_visible()
        await check("guide done (3 steps)", guide_hidden)

        # ================= 3. 里程碑: 第2层 27 块有限矿 =================
        ms_vis = await page.locator('[data-panel="milestone"]').is_visible()
        await check("milestone modal at 20 XP", ms_vis)
        await page.locator('[data-act="milestone-continue"]').click()
        await page.wait_for_timeout(300)
        lvname = await page.locator("#lvname").text_content()
        await check("layer 2 after milestone", "2层" in lvname, lvname)
        rem = await page.locator("#remaining").text_content()
        await check("layer2 finite 27 ores", "27" in rem, rem)

        # ================= 4. F-8 矿工卡: 解锁未购买不显示 undefined =================
        mlv = await page.locator("#minerlv").text_content()
        mdesc = await page.locator("#minerdesc").text_content()
        await check("F-8 miner card shows 待解锁 (unlocked, not bought)", mlv == "待解锁", mlv)
        await check("F-8 miner desc has rate, no undefined", "0.5" in mdesc and "undefined" not in mdesc, mdesc)

        # ================= 5. F-3 重roll不吞矿: 面板延迟期内挖掉邻矿后插入 =================
        n0 = await js("window.__MINE__.state().layer.ores.length")
        await check("layer2 starts with 27 ores (N)", n0 == 27, n0)
        await page.evaluate("window.__MINE__.forceNext('fake')")
        await tap_first_ore(wait=150)
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_ore(2, wait=150)          # 900ms 延迟窗口内再挖掉第3块矿
        await page.wait_for_timeout(1100)   # 假矿面板弹出
        fake_vis = await page.locator('[data-panel="fake"]').is_visible()
        await check("F-3 fake panel appears (900ms delay + shrunk array)", fake_vis)
        n1 = await js("window.__MINE__.state().layer.ores.length")
        await check("F-3 array shrunk by 2 before reroll (N-2)", n1 == n0 - 2, n1)
        await page.evaluate("window.__MINE__.forceNext('iron')")
        await page.locator('[data-act="reroll-free"]').click()
        await page.wait_for_timeout(400)
        n2 = await js("window.__MINE__.state().layer.ores.length")
        await check("F-3 reroll INSERTS ore (N-1), neighbor not swallowed", n2 == n0 - 1, "N=%d n1=%d n2=%d" % (n0, n1, n2))
        kind0 = await js("window.__MINE__.state().layer.ores[0].kind")
        await check("F-3 rerolled ore is iron at index 0", kind0 == "iron", kind0)

        # ================= 6. F-3 广告重roll: 真实生效并计数 =================
        await page.evaluate("window.__MINE__.setFakeCount(3)")
        await page.evaluate("window.__MINE__.forceNext('fake')")
        await tap_first_ore(wait=1200)
        ad_btn = await page.locator('[data-act="reroll-ad"]').count()
        await check("F-3 fake#4 shows AD reroll (3:1)", ad_btn == 1, ad_btn)
        n_before_ad = await js("window.__MINE__.state().layer.ores.length")
        await page.locator('[data-act="reroll-ad"]').click()
        await page.wait_for_timeout(300)
        ad_vis = await page.locator('[data-panel="ad"]').is_visible()
        await check("simulated rewarded video opens", ad_vis)
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        n_after_ad = await js("window.__MINE__.state().layer.ores.length")
        await check("F-3 ad reroll inserts ore (+1)", n_after_ad == n_before_ad + 1, "%d -> %d" % (n_before_ad, n_after_ad))
        adc = await js("window.__MINE__.state().adCounts.reroll")
        await check("F-3 adCounts.reroll == 1", adc == 1, adc)
        await page.screenshot(path=SHOT_DIR + "/fix-02-reroll.png")

        # ================= 7. F-1 最后一块矿是假矿: 先给重roll, 再结算枯竭 =================
        await page.evaluate("window.__MINE__.setCoins(0)")
        await page.evaluate("window.__MINE__.trimLayer(1)")
        qcnt = await page.locator('[data-last-ore]').count()
        await check("last ore carries ? badge", qcnt == 1, qcnt)
        await page.evaluate("window.__MINE__.forceNext('fake')")
        await tap_first_ore(wait=1200)
        fake_vis = await page.locator('[data-panel="fake"]').is_visible()
        gap_before = await page.locator('[data-panel="gap"]').is_visible()
        await check("F-1 last fake -> REROLL panel first (not depletion)", fake_vis and not gap_before)
        await page.locator('[data-act="fake-dismiss"]').click()
        await page.wait_for_timeout(300)
        gap_after = await page.locator('[data-panel="gap"]').is_visible()
        await check("F-1 after reroll declined -> depletion panel settles", gap_after)
        await page.locator('[data-panel="gap"] [data-act="layer-restart"]').click()
        await page.wait_for_timeout(400)
        rem2 = await page.locator("#remaining").text_content()
        await check("layer restarted (27 ores again)", "27" in rem2, rem2)

        # ================= 8. F-6 确定性差一点: 枯竭必弹「差 X 给 X+1」广告位 =================
        await page.evaluate("window.__MINE__.setDrillLv(2)")
        await page.evaluate("window.__MINE__.setCoins(0)")
        await page.evaluate("window.__MINE__.trimLayer(1)")
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=500)
        gap_vis = await page.locator('[data-panel="gap"]').is_visible()
        await check("F-6 depletion always shows gap panel", gap_vis)
        gtxt = await page.locator("#gap-text").text_content()
        await check("F-6 gap text '差 14 金币' (short=15-mined+1, beyond old window 5)", "14" in gtxt, gtxt)
        gbtn = await page.locator("#gapAdBtn").text_content()
        await check("F-6 gap ad gives 15 coins (X+1)", "15" in gbtn, gbtn)
        await page.locator('[data-panel="gap"] [data-act="gap-ad"]').click()
        await page.wait_for_timeout(300)
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        coins = await js("window.__MINE__.state().coins")
        await check("F-6 gap ad pays exactly short+1 (0 -> 16)", coins == 16, coins)
        adc = await js("window.__MINE__.state().adCounts.gap")
        await check("F-6 adCounts.gap == 1", adc == 1, adc)
        await page.screenshot(path=SHOT_DIR + "/fix-03-gap.png")
        await page.evaluate("window.__MINE__.setCoins(13)")
        pulse = await page.evaluate("document.getElementById('coins').classList.contains('pulse')")
        await check("F-6 counter pulses within 3 of upgrade cost (13/15)", pulse)
        await page.locator('[data-panel="gap"] [data-act="layer-restart"]').click()
        await page.wait_for_timeout(400)

        # ================= 9. F-10 稀有矿视觉区分(按品种着色) + 收集 =================
        await page.evaluate("window.__MINE__.setDrillLv(1)")
        await page.evaluate("window.__MINE__.forceNext('rare:amethyst')")
        await tap_first_ore(wait=300)
        rare_cls = await page.locator('[data-ore-kind="rare"].ore-rare-amethyst').count()
        await check("F-10 rare ore carries per-kind class ore-rare-amethyst", rare_cls >= 1, rare_cls)
        await page.screenshot(path=SHOT_DIR + "/fix-04-rare.png")
        for _ in range(4):
            await tap_first_ore(wait=250)
        ameth = await js("window.__MINE__.state().inventory.amethyst")
        await check("F-10 rare amethyst collected", ameth == 1, ameth)

        # ================= 10. F-10 关键数字张力: 剩 10/8/3 提示 + 里程碑差一点 =================
        await page.evaluate("window.__MINE__.trimLayer(10)")
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=200)
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=200)
        toast_txt = await page.locator("#toast").text_content()
        await check("F-10 tension toast at 8 ores left", "还剩 8 块" in (toast_txt or ""), toast_txt)
        await page.evaluate("window.__MINE__.setXP(92)")
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=300)
        xp_now = await js("window.__MINE__.state().xp")
        toast_txt2 = await page.locator("#toast").text_content()
        await check("F-10 milestone near toast (93/100, diff 7)", xp_now == 93 and "扩建还差 7" in (toast_txt2 or ""), "xp=%s toast=%s" % (xp_now, toast_txt2))

        # ================= 11. 背包满 + 稀有矿 → 看广告扩容 (回归) =================
        await page.evaluate("window.__MINE__.setXP(50)")  # 避免与 100XP 里程碑同屏覆盖
        await page.evaluate("window.__MINE__.fillInventory()")
        await page.evaluate("window.__MINE__.setDrillLv(5)")
        coins_before = await js("window.__MINE__.state().coins")
        await page.evaluate("window.__MINE__.forceNext('rare:amethyst')")
        await tap_first_ore(wait=500)
        pf_vis = await page.locator('[data-panel="packfull"]').is_visible()
        await check("pack-full panel on rare drop", pf_vis)
        coins_after = await js("window.__MINE__.state().coins")
        await check("rare ore value granted (+25)", coins_after == coins_before + 25, "%s -> %s" % (coins_before, coins_after))
        await page.locator('[data-panel="packfull"] [data-act="pack-ad"]').click()
        await page.wait_for_timeout(300)
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        slots = await js("window.__MINE__.state().packSlots")
        ameth = await js("window.__MINE__.state().inventory.amethyst")
        await check("pack slots 6->9", slots == 9, slots)
        await check("amethyst collected after expand", ameth == 7, ameth)
        adc = await js("window.__MINE__.state().adCounts.pack")
        await check("adCounts.pack == 1", adc == 1, adc)

        # ================= 12. 限时矿脉 / 任务 / 排行 (回归) =================
        await page.evaluate("window.__MINE__.forceEvent()")
        await page.wait_for_timeout(300)
        vein_vis = await page.locator("#veinstrip").is_visible()
        await check("vein strip appears", vein_vis)
        await page.locator('[data-vein-ore]').first.click()
        await page.wait_for_timeout(400)
        qv = await js("window.__MINE__.state().questVein")
        await check("daily quest vein progress == 1", qv == 1, qv)
        await page.locator('[data-act="quest"]').click()
        await page.wait_for_timeout(250)
        q_text = await page.locator('[data-panel="quest"]').text_content()
        await check("daily quest list rendered", "紫水晶" in q_text and "限时矿脉" in q_text)
        await close_panel_backdrop()
        await page.locator('[data-act="rank"]').click()
        await page.wait_for_timeout(250)
        rank_vis = await page.locator('[data-panel="rank"]').is_visible()
        await check("rank panel opens", rank_vis)
        ranktab_h = await js("document.querySelector('.ranktab').getBoundingClientRect().height")
        await check("F-5 ranktab >= 44px", ranktab_h >= 44, "%.1f" % ranktab_h)
        me_rows = await page.locator('[data-rank="player"]').count()
        await check("player ranked (asset tab)", me_rows == 1, me_rows)
        await page.locator('[data-act="tab-net"]').click()
        await page.wait_for_timeout(250)
        me_rows2 = await page.locator('[data-rank="player"]').count()
        await check("player ranked (net tab)", me_rows2 == 1, me_rows2)
        await close_panel_backdrop()

        # ================= 13. F-7 分享文案 + 限频 + F-5 面板按钮 =================
        await page.locator('[data-act="share-card"]').click()
        await page.wait_for_timeout(300)
        card_vis = await page.locator('[data-share-card]').is_visible()
        await check("share card shown", card_vis)
        scopy = await page.locator("#sc-copy").text_content()
        await check("F-7 copy invites challenge, no 病句", "敢来比" in scopy and "几座" not in scopy and "你的矿场" not in scopy, scopy)
        btn_h = await js("document.querySelector('[data-panel=\"share\"] .btn').getBoundingClientRect().height")
        await check("F-5 panel button >= 44px", btn_h >= 44, "%.1f" % btn_h)
        await page.screenshot(path=SHOT_DIR + "/fix-05-share.png")
        coins_before = await js("window.__MINE__.state().coins")
        for i in range(3):
            await page.locator('[data-act="share"]').click()
            await page.wait_for_timeout(350)
        coins_3 = await js("window.__MINE__.state().coins")
        await check("3 shares each +20", coins_3 - coins_before >= 59.5, "delta %s" % (coins_3 - coins_before))
        sc = await js("window.__MINE__.state().shareCount")
        await check("shareCount == 3", sc == 3, sc)
        await page.locator('[data-act="share"]').click()
        await page.wait_for_timeout(400)
        sc4 = await js("window.__MINE__.state().shareCount")
        await check("4th share blocked (limit 3/day)", sc4 == 3, "shareCount %s" % sc4)
        toast_txt = await page.locator("#toast").text_content()
        await check("block toast shown", "上限" in (toast_txt or ""), toast_txt)
        await close_panel_backdrop()

        # ================= 14. F-5 底部 tab / mute / reset ≥44px =================
        tab_hs = await js("[...document.querySelectorAll('.tab')].map(e=>e.getBoundingClientRect().height)")
        await check("F-5 all 4 bottom tabs >= 44px", len(tab_hs) == 4 and min(tab_hs) >= 44, "%.1f" % min(tab_hs))
        mute_h = await js("document.getElementById('mutebtn').getBoundingClientRect().height")
        reset_h = await js("document.getElementById('resetbtn').getBoundingClientRect().height")
        await check("F-5 mute button >= 44px", mute_h >= 44, "%.1f" % mute_h)
        await check("F-5 reset button >= 44px", reset_h >= 44, "%.1f" % reset_h)

        # ================= 15. F-4 离线收益: 矿工1级 2h=+1800(在线50%/h) + ×2 广告 =================
        await page.evaluate("window.__MINE__.setCoins(200)")
        await page.locator('[data-act="upgrade-miner"]').click()
        await page.wait_for_timeout(300)
        mlv = await js("window.__MINE__.state().minerLv")
        await check("miner unlocked & Lv1", mlv == 1, mlv)
        mdesc = await page.locator("#minerdesc").text_content()
        await check("F-8 miner desc shows 0.5/s after purchase", "0.5" in mdesc, mdesc)
        coins_before = await js("window.__MINE__.state().coins")
        try:
            await js("window.__MINE__.simulateOffline(120)")
        except Exception:
            pass  # navigation destroys context mid-evaluate
        await page.wait_for_timeout(800)
        await fast_ads()
        off_vis = await page.locator('[data-panel="offline"]').is_visible()
        await check("offline settlement shown on return", off_vis)
        amt = await page.locator("#offline-amount").text_content()
        await check("F-4 offline base 2h = +1800 (0.5/s*60*0.5*120)", "1800" in amt, amt)
        h2 = await page.locator('[data-panel="offline"] h2').text_content()
        await check("F-4 welcome-back headline shown", "欢迎回来" in h2, h2)
        await page.screenshot(path=SHOT_DIR + "/fix-06-offline.png")
        await page.locator('[data-act="offline-x2"]').wait_for(timeout=6000)
        await page.locator('[data-act="offline-x2"]').click()
        await page.wait_for_timeout(300)
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        coins_after = await js("window.__MINE__.state().coins")
        delta = coins_after - coins_before
        # 3600 = 基础1800 + 翻倍1800; 额外为结算瞬间触发的今日目标阶段奖励(+50/+150)与矿工跳动
        await check("F-4 offline x2 total +3600 (+day-target reward ok)", 3600 <= delta <= 3900, "delta %s" % delta)
        adc = await js("window.__MINE__.state().adCounts.offline")
        await check("adCounts.offline == 1", adc == 1, adc)
        await check("offline panel auto-closes after x2 claim", await page.locator('.panel.active').count() == 0)

        # ================= 15.5 P-1 离线文案与 8h 封顶一致 (离线 10h) =================
        # 矿工1级 0.5/s → 30/分 → 8h 封顶 = 30×0.5×480 = +7200；文案不得再显示「10 小时」
        try:
            await js("window.__MINE__.simulateOffline(600)")
        except Exception:
            pass  # navigation destroys context mid-evaluate
        await page.wait_for_timeout(800)
        await fast_ads()
        off_vis = await page.locator('[data-panel="offline"]').is_visible()
        await check("P-1 offline 10h panel shown", off_vis)
        amt = await page.locator("#offline-amount").text_content()
        await check("P-1 offline 10h amount capped at 8h = +7200", "7200" in amt, amt)
        otime = await page.locator("#offline-time").text_content()
        await check("P-1 copy mentions 上限/8 小时 (consistent with cap)", "上限" in otime and "8 小时" in otime, otime)
        await check("P-1 copy no longer claims 10 小时", "10 小时" not in otime, otime)
        await page.locator('[data-act="offline-close"]').click()
        await page.wait_for_timeout(300)

        # ================= 15.6 B-2 限时矿脉 5 块点完立即收尾 (无幽灵项) =================
        # 关键操作：每次都点 DOM 第 2 块（旧下标 1,2,3,4…）——splice 后旧 data-vein-ore
        # 下标失配会越界 no-op，残留幽灵项；修复后按 DOM 位置定位，5 次必收尾
        # 前置：XP 压到低位——每块矿脉 +10 XP，连点 5 块会冲过 100 触发第3层里程碑面板
        # 遮挡矿脉（实测 XP 70→100 在第 3 点击穿）；背包已满的 packfull 面板在循环内点掉
        await page.evaluate("window.__MINE__.setXP(5)")
        await page.evaluate("window.__MINE__.forceEvent()")
        await page.wait_for_timeout(300)
        vein_cnt = await page.locator('[data-vein-ore]').count()
        await check("B-2 vein spawns 5 ores", vein_cnt == 5, vein_cnt)
        for _ in range(5):
            n = await page.locator('[data-vein-ore]').count()
            await page.locator('[data-vein-ore]').nth(min(1, n - 1)).click()
            await page.wait_for_timeout(150)
            # 前序章节背包已近满：稀有矿触发的 packfull 面板会 pause 游戏并盖住矿脉，
            # 点掉后继续（收尾断言在 5 连点之后统一校验）
            if await page.locator('[data-panel="packfull"].active').count() > 0:
                await page.locator('[data-act="pack-decline"]').click()
                await page.wait_for_timeout(250)
        vein_gone = not await page.locator("#veinstrip").is_visible()
        vein_state = await js("window.__MINE__.state().veinActive")
        await check("B-2 after 5 clicks vein finishes immediately (strip hidden)", vein_gone, vein_state)
        await check("B-2 veinActive cleared (no ghost item)", vein_state is None, vein_state)
        grid_left = await js("document.getElementById('veingrid').children.length")
        await check("B-2 no ghost buttons left in grid", grid_left == 0, grid_left)
        await page.wait_for_timeout(1500)
        vein_still_gone = not await page.locator("#veinstrip").is_visible()
        await check("B-2 strip stays hidden 1.5s later (no 60s empty hang)", vein_still_gone)
        # 事件系统未卡死：可再次触发新矿脉
        await page.evaluate("window.__MINE__.forceEvent()")
        await page.wait_for_timeout(300)
        vein_cnt2 = await page.locator('[data-vein-ore]').count()
        await check("B-2 vein event can re-trigger (5 ores again)", vein_cnt2 == 5, vein_cnt2)

        # ================= 15.7 P-2 差一点面板: 小数金币整数化展示 =================
        # 注入纯净存档重载（清空矿脉/矿工/背包干扰，且 `.ore` 选择器不再误中矿脉按钮）：
        # 默认钻头1级→下一升级 10 金币；挖矿本身 +1 → 金币 8.8 挖后 9.8 → 差额 ceil = 1
        # （旧代码 10-9.8=0.1999999999999993 长尾直出「差 0.1999999999999993 金币」）
        await page.evaluate("window.__MINE__.forceSave({mineLevel:2, guideDone:true})")
        await rel()
        await page.evaluate("window.__MINE__.setCoins(8.8)")
        await page.evaluate("window.__MINE__.trimLayer(1)")
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=500)
        gap_vis = await page.locator('[data-panel="gap"]').is_visible()
        await check("P-2 gap panel appears with fractional coins", gap_vis)
        gtxt = await page.locator("#gap-text").text_content()
        gbtn = await page.locator("#gapAdBtn").text_content()
        await check("P-2 gap text integerized (还差 1 金币, no long tail)", gtxt == "距升级还差 1 金币", gtxt)
        await check("P-2 gap ad button integer (2 coins)", gbtn == "📺 看广告获得 2 金币 🪙", gbtn)
        await page.locator('[data-panel="gap"] [data-act="layer-restart"]').click()
        await page.wait_for_timeout(400)

        # ================= 16. F-2 清空存档真清空 (确认后不再被 beforeunload 回写) =================
        await page.evaluate("window.__MINE__.setCoins(999)")
        await page.locator('#resetbtn').click()
        await page.wait_for_timeout(2000)
        await fast_ads()
        coins = coins_of(await page.locator("#coins").text_content())
        await check("F-2 coins reset to 0 after confirm", coins == 0, coins)
        step1 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("F-2 guide restarts (fresh state)", step1 == "1", step1)
        save_now = await js("localStorage.getItem('wmkuang_save_v1')")
        # 清空后 2 秒周期存档会把「全新状态」正常写回；关键是状态必须已归零而非旧状态残留
        fresh_save = save_now is None or '"coins":0' in save_now
        await check("F-2 save is cleared/fresh after confirm (no stale state)", fresh_save, (save_now or "")[:80])
        marker = await js("localStorage.getItem('wmkuang_reset_pending')")
        await check("F-2 reset marker consumed", marker is None, marker)

        # ================= 17. F-1 旧空层存档加载自愈 (软锁存档迁移) =================
        await js("window.__MINE__.forceSave({coins:5, mineLevel:2, layer:{depth:2, ores:[]}, guideDone:true})")
        await rel()
        cnt = await ore_count()
        coins = await js("window.__MINE__.state().coins")
        await check("F-1 broken empty-layer save heals to 27 ores", cnt == 27, cnt)
        await check("F-1 healed save keeps coins (5)", coins == 5, coins)
        await js("window.__MINE__.forceSave({coins:3, mineLevel:1, layer:{depth:1, ores:[]}, guideDone:true})")
        await rel()
        cnt = await ore_count()
        await check("F-1 broken layer1 save heals to 3 ores", cnt == 3, cnt)

        # ================= 18. F-4 新手兜底: 无矿工离线也必有结算 (2h=+120) =================
        await page.evaluate("localStorage.clear()")
        await rel()
        try:
            await js("window.__MINE__.simulateOffline(120)")
        except Exception:
            pass
        await page.wait_for_timeout(800)
        await fast_ads()
        off_vis = await page.locator('[data-panel="offline"]').is_visible()
        await check("F-4 newbie (no miner) gets offline panel too", off_vis)
        amt = await page.locator("#offline-amount").text_content()
        await check("F-4 newbie floor 2h = +120 (lvl1*2/min*0.5*120)", "120" in amt, amt)
        h2 = await page.locator('[data-panel="offline"] h2').text_content()
        await check("F-4 newbie sees welcome-back headline", "欢迎回来" in h2, h2)
        await page.locator('[data-act="offline-close"]').click()
        await page.wait_for_timeout(300)

        # ================= 19. console errors + 溢出 + 320 可玩 =================
        await check("zero console errors", len(console_errors) == 0, console_errors[:3])
        ow375 = await page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
        await check("no horizontal overflow @375", ow375 <= 0, ow375)
        await page.screenshot(path=SHOT_DIR + "/fix-07-final-375.png")
        await page.set_viewport_size({"width": 320, "height": 568})
        await page.wait_for_timeout(400)
        ow320 = await page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
        await check("no horizontal overflow @320", ow320 <= 0, ow320)
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=400)
        await check("playable at 320px", await ore_count() >= 1)
        await page.screenshot(path=SHOT_DIR + "/fix-08-final-320.png")

        # ================= 汇总 =================
        passed = sum(1 for r in results if r[1])
        print("\n==== E2E 修复轮2: %d 通过, %d 失败 / %d 项 ====" % (passed, len(results) - passed, len(results)))
        failed = [r for r in results if not r[1]]
        for f in failed:
            print("FAILED:", f)
        await browser.close()
        sys.exit(0 if passed == len(results) else 1)

if __name__ == "__main__":
    asyncio.run(main())
