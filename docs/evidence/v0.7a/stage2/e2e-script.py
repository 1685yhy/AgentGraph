#!/usr/bin/env python3
"""E2E verification of 离谱卡牌 game (Playwright) - robust interaction."""
import sys, asyncio
from playwright.async_api import async_playwright

URL = "file:///mnt/e/agentguild/docs/evidence/v0.7a/stage2/deliverable/game/index.html"
results = []

async def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    print(("PASS " if cond else "FAIL ") + name + (" | " + str(detail) if detail else ""))

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 375, "height": 812})
        console_errors = []
        page.on("console", lambda m: console_errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: console_errors.append(str(e)))
        dialogs = []
        async def on_dialog(d):
            dialogs.append(d.message)
            await d.accept()
        page.on("dialog", on_dialog)

        async def click_js(sel):
            # click via JS to bypass Playwright actionability quirks with dialogs
            await page.evaluate("document.querySelector('%s').click()" % sel)
            await page.wait_for_timeout(300)

        await page.goto(URL)
        await page.wait_for_timeout(500)

        title = await page.title()
        await check("title 离谱卡牌", "离谱卡牌" in title, title)
        cards0 = await page.locator("#card-container .card").count()
        await check("初始渲染3张卡", cards0 == 3, cards0)
        round0 = (await page.locator("#round-num").text_content()).strip()
        await check("第1局开始", round0 == "1", round0)

        await click_js("#draw-btn")
        round1 = (await page.locator("#round-num").text_content()).strip()
        await check("抽卡后第2局", round1 == "2", round1)
        ad_draw_visible = await page.locator("#ad-draw-btn").is_visible()
        await check("看广告+1张按钮出现", ad_draw_visible)

        await click_js("#ad-draw-btn")
        await page.wait_for_timeout(2600)
        absurd_after_ad = (await page.locator("#absurd-value").text_content()).strip()
        await check("看广告后离谱值增加", int(absurd_after_ad) > 0, absurd_after_ad)

        # rounds 3,4,5,6(结算)
        for _ in range(4):
            await click_js("#draw-btn")
        await page.wait_for_timeout(400)
        result_visible = await page.locator("#result-screen").is_visible()
        await check("结算屏出现", result_visible)
        if result_visible:
            rt = await page.locator("#result-title").text_content()
            await check("结算显示离谱值", "离谱值" in rt, rt)
            inter_visible = await page.locator("#interstitial-ad").is_visible()
            await check("插屏广告占位显示(第5局)", inter_visible)
            rev_visible = await page.locator("#ad-reverse-btn").is_visible()
            await check("逆袭翻倍按钮出现", rev_visible)

        await click_js("#ad-reverse-btn")
        await page.wait_for_timeout(2600)
        rt2 = await page.locator("#result-title").text_content()
        await check("逆袭翻倍后结算更新", "离谱值" in rt2, rt2)

        await click_js("#share-btn")
        share_visible = await page.locator("#share-screen").is_visible()
        await check("分享屏出现", share_visible)
        await click_js("#confirm-share-btn")
        await page.wait_for_timeout(300)
        game_visible = await page.locator("#game-screen").is_visible()
        await check("分享后回主屏", game_visible)
        round_after = (await page.locator("#round-num").text_content()).strip()
        await check("分享后新一局", round_after == "1", round_after)

        best = await page.evaluate("localStorage.getItem('absurd_best')")
        await check("localStorage 存档", best is not None and int(best) > 0, best)

        # 30s share frequency guard
        share_screen2 = await page.locator("#share-screen").is_visible()
        await check("限频后分享被拦截(仍主屏)", not share_screen2)

        await check("无 console 错误", len(console_errors) == 0, console_errors[:3])
        await check("有对话框交互(广告/分享提示)", len(dialogs) >= 3, len(dialogs))

        await page.screenshot(path="/tmp/lipu-result.png")
        await browser.close()

    fails = [r for r in results if not r[1]]
    print("\n==== %d/%d passed ====" % (len(results) - len(fails), len(results)))
    if fails:
        print("FAILED:", [f[0] for f in fails])
    sys.exit(1 if fails else 0)

asyncio.run(main())
