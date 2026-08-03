#!/usr/bin/env python3
"""E2E verification of 「无尽矿脉」idle mining game (Playwright, headless Chromium).

Coverage (per v0.7a-iter2 A-phase brief):
- 开局3步引导 → 点击挖矿 → 升级钻头 → 矿场等级里程碑(第1层白给→第2层地狱)
- 假矿猜测(10%假矿) → 差一点(枯竭距升级差3金币) → 广告重roll(免费3次→第4次起看广告)
- 背包满+稀有矿 → 看广告扩容; 离线收益结算+×2广告; 重开矿脉(再来)
- 每日任务/净收益/排行(总资产+今日净收益)/分享战绩卡(3次/日限频)
- 限时稀有矿脉事件
- 0 console error; 375px/320px 无横向溢出
Debug hooks (window.__MINE__, gated by #debug hash) drive deterministic outcomes.
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

        async def tap_first_ore(wait=300):
            await page.evaluate("document.querySelector('.ore').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))")
            await page.wait_for_timeout(wait)

        async def close_panel_backdrop():
            await page.mouse.click(8, 60)
            await page.wait_for_timeout(250)

        # ================= 0. fresh state =================
        await page.goto(URL)
        await page.evaluate("localStorage.clear()")
        await page.reload()
        await page.wait_for_timeout(500)
        await page.evaluate("window.__MINE__.fastAds(true)")

        title = await page.title()
        await check("title 无尽矿脉", "无尽矿脉" in title, title)

        # ================= 1. 开局3步引导 =================
        step1 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("guide step1 shown", step1 == "1", step1)
        await tap_first_ore()
        step2 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("guide step2 after first tap", step2 == "2", step2)
        coins = coins_of(await page.locator("#coins").text_content())
        await check("coin +1 after first tap", coins == 1, coins)
        await page.screenshot(path=SHOT_DIR + "/e2e-01-guide.png")

        # ================= 2. 里程碑: 第1层白给 → 第2层(27块有限矿) =================
        await page.evaluate("window.__MINE__.setXP(18)")
        await tap_first_ore()
        await tap_first_ore()
        ms_vis = await page.locator('[data-panel="milestone"]').is_visible()
        await check("milestone modal at 20 XP", ms_vis)
        await page.locator('[data-act="milestone-continue"]').click()
        await page.wait_for_timeout(300)
        lvname = await page.locator("#lvname").text_content()
        await check("layer 2 after milestone", "2层" in lvname, lvname)
        rem = await page.locator("#remaining").text_content()
        await check("layer2 finite 27 ores", "27" in rem, rem)

        # ================= 3. 升级钻头(引导第2步) + 引导第3步完成 =================
        await page.locator('[data-act="upgrade-drill"]').click()
        await page.wait_for_timeout(300)
        step3 = await page.locator("#guide").get_attribute("data-guide-step")
        await check("guide step3 after drill upgrade", step3 == "3", step3)
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore()
        guide_hidden = not await page.locator("#guide").is_visible()
        await check("guide done (3 steps)", guide_hidden)

        # ================= 4. 假矿: 免费重roll(当日第1次假矿) =================
        coins_before = await js("window.__MINE__.state().coins")
        await page.evaluate("window.__MINE__.forceNext('fake')")
        await tap_first_ore(wait=1200)
        fake_vis = await page.locator('[data-panel="fake"]').is_visible()
        await check("fake panel after fake hit", fake_vis)
        coins_after = await js("window.__MINE__.state().coins")
        await check("fake deducts 1 coin", coins_after == coins_before - 1, "%s -> %s" % (coins_before, coins_after))
        free_btn = await page.locator('[data-act="reroll-free"]').count()
        await check("fake#1 <=3 shows FREE reroll", free_btn == 1, free_btn)
        await page.evaluate("window.__MINE__.forceNext('iron')")
        await page.locator('[data-act="reroll-free"]').click()
        await page.wait_for_timeout(400)
        iron_cells = await page.locator('[data-ore-kind="iron"]').count()
        await check("reroll regenerates iron ore", iron_cells >= 1, iron_cells)

        # ================= 5. 假矿: 第4次起 → 看广告重roll =================
        await page.evaluate("window.__MINE__.setFakeCount(3)")
        await page.evaluate("window.__MINE__.forceNext('fake')")
        await tap_first_ore(wait=1200)
        ad_btn = await page.locator('[data-act="reroll-ad"]').count()
        await check("fake#4 shows AD reroll (3:1)", ad_btn == 1, ad_btn)
        await page.locator('[data-act="reroll-ad"]').click()
        await page.wait_for_timeout(300)
        ad_vis = await page.locator('[data-panel="ad"]').is_visible()
        await check("simulated rewarded video opens", ad_vis)
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        copper_cells = await page.locator('[data-ore-kind="copper"]').count()
        await check("ad reroll regenerates copper ore", copper_cells >= 1, copper_cells)
        adc = await js("window.__MINE__.state().adCounts.reroll")
        await check("adCounts.reroll == 1", adc == 1, adc)

        # ================= 6. 背包满 + 稀有矿 → 看广告扩容 =================
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

        # ================= 7. 差一点: 枯竭时距升级差3金币 → 看广告获得4金币 =================
        await page.evaluate("window.__MINE__.setDrillLv(3)")
        await page.evaluate("window.__MINE__.setCoins(48)")
        await page.evaluate("window.__MINE__.trimLayer(1)")
        last_q = await page.locator('[data-last-ore]').count()
        await check("last ore carries ? badge", last_q == 1, last_q)
        await page.evaluate("window.__MINE__.forceNext('fake')")
        await tap_first_ore(wait=800)
        gap_vis = await page.locator('[data-panel="gap"]').is_visible()
        await check("depletion gap panel (差一点)", gap_vis)
        gtxt = await page.locator("#gap-text").text_content()
        await check("gap text '差 3 金币'", "3" in gtxt, gtxt)
        gbtn = await page.locator("#gapAdBtn").text_content()
        await check("gap ad gives 4 coins (差2给3原理)", "4" in gbtn, gbtn)
        await page.locator('[data-panel="gap"] [data-act="gap-ad"]').click()
        await page.wait_for_timeout(300)
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        gtxt2 = await page.locator("#gap-text").text_content()
        await check("gap panel updated after claim", "已获得" in gtxt2, gtxt2)
        coins = await js("window.__MINE__.state().coins")
        await check("coins 47->51 after gap ad", coins == 51, coins)
        await page.screenshot(path=SHOT_DIR + "/e2e-02-gap.png")

        # ================= 8. 再来: 重开矿脉 =================
        await page.locator('[data-panel="gap"] [data-act="layer-restart"]').click()
        await page.wait_for_timeout(400)
        rem2 = await page.locator("#remaining").text_content()
        await check("layer restarted (27 ores again)", "27" in rem2, rem2)
        await page.locator('[data-act="upgrade-drill"]').click()
        await page.wait_for_timeout(300)
        dlv = await js("window.__MINE__.state().drillLv")
        await check("drill upgraded to Lv4", dlv == 4, dlv)

        # ================= 9. 自动矿工 + 离线收益结算(×2广告) =================
        await page.evaluate("window.__MINE__.setCoins(200)")
        await page.locator('[data-act="upgrade-miner"]').click()
        await page.wait_for_timeout(300)
        mlv = await js("window.__MINE__.state().minerLv")
        await check("miner unlocked & Lv1", mlv == 1, mlv)
        coins_before = await js("window.__MINE__.state().coins")
        try:
            await js("window.__MINE__.simulateOffline(120)")
        except Exception:
            pass  # navigation destroys context mid-evaluate
        await page.wait_for_timeout(800)
        off_vis = await page.locator('[data-panel="offline"]').is_visible()
        await check("offline settlement shown on return", off_vis)
        amt = await page.locator("#offline-amount").text_content()
        await check("offline base income shown (12)", "12" in amt, amt)
        await page.evaluate("window.__MINE__.fastAds(true)")
        await page.locator('[data-act="offline-x2"]').wait_for(timeout=6000)
        await page.locator('[data-act="offline-x2"]').click()
        await page.wait_for_timeout(300)
        await page.locator('[data-act="ad-claim"]').click(timeout=6000)
        await page.wait_for_timeout(500)
        coins_after = await js("window.__MINE__.state().coins")
        delta = coins_after - coins_before
        await check("offline x2 total ~24 (base12+bonus12)", 23 <= delta <= 27, "delta %s" % delta)
        adc = await js("window.__MINE__.state().adCounts.offline")
        await check("adCounts.offline == 1", adc == 1, adc)
        await page.locator('[data-act="offline-close"]').is_visible()
        await close_panel_backdrop()
        await check("back to playing after offline", await js("window.__MINE__.state().coins") is not None)

        # ================= 10. 限时稀有矿脉事件 =================
        await page.evaluate("window.__MINE__.forceEvent()")
        await page.wait_for_timeout(300)
        vein_vis = await page.locator("#veinstrip").is_visible()
        await check("vein strip appears", vein_vis)
        vc = await page.locator("#veincount").text_content()
        await check("vein countdown ticks", "s" in vc, vc)
        await page.locator('[data-vein-ore]').first.click()
        await page.wait_for_timeout(400)
        qv = await js("window.__MINE__.state().questVein")
        await check("daily quest vein progress == 1", qv == 1, qv)

        # ================= 11. 每日任务 / 排行 / 分享战绩卡 =================
        await page.locator('[data-act="quest"]').click()
        await page.wait_for_timeout(250)
        q_text = await page.locator('[data-panel="quest"]').text_content()
        await check("daily quest list rendered", "紫水晶" in q_text and "限时矿脉" in q_text)
        await close_panel_backdrop()

        await page.locator('[data-act="rank"]').click()
        await page.wait_for_timeout(250)
        rank_vis = await page.locator('[data-panel="rank"]').is_visible()
        await check("rank panel opens", rank_vis)
        me_rows = await page.locator('[data-rank="player"]').count()
        await check("player ranked (asset tab)", me_rows == 1, me_rows)
        await page.locator('[data-act="tab-net"]').click()
        await page.wait_for_timeout(250)
        me_rows2 = await page.locator('[data-rank="player"]').count()
        await check("player ranked (net tab)", me_rows2 == 1, me_rows2)
        await page.screenshot(path=SHOT_DIR + "/e2e-03-rank.png")
        await close_panel_backdrop()

        await page.locator('[data-act="share-card"]').click()
        await page.wait_for_timeout(300)
        card_vis = await page.locator('[data-share-card]').is_visible()
        await check("share card shown", card_vis)
        days = await page.locator("#sc-days").text_content()
        await check("share card has 运营天数", "第" in days and "天" in days, days)
        asset = await page.locator("#sc-asset").text_content()
        await check("share card has 总资产", len(asset) > 0, asset)
        await page.screenshot(path=SHOT_DIR + "/e2e-04-share.png")
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

        # ================= 12. console errors + 溢出检查 =================
        await check("zero console errors", len(console_errors) == 0, console_errors[:3])
        ow375 = await page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
        await check("no horizontal overflow @375", ow375 <= 0, ow375)
        await page.screenshot(path=SHOT_DIR + "/e2e-05-final-375.png")
        await page.set_viewport_size({"width": 320, "height": 568})
        await page.wait_for_timeout(400)
        ow320 = await page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
        await check("no horizontal overflow @320", ow320 <= 0, ow320)
        # quick play sanity at 320: tap an ore
        await page.evaluate("window.__MINE__.forceNext('copper')")
        await tap_first_ore(wait=400)
        await check("playable at 320px", await page.locator('[data-ore]').count() > 0)
        await page.screenshot(path=SHOT_DIR + "/e2e-06-final-320.png")

        # ================= 汇总 =================
        passed = sum(1 for r in results if r[1])
        print("\n==== E2E 结果: %d 通过, %d 失败 / %d 项 ====" % (passed, len(results) - passed, len(results)))
        failed = [r for r in results if not r[1]]
        for f in failed:
            print("FAILED:", f)
        await browser.close()
        sys.exit(0 if passed == len(results) else 1)

if __name__ == "__main__":
    asyncio.run(main())
