#!/usr/bin/env python3
"""E2E verification of 离谱卡牌 game (Playwright) — fix round 1 coverage.

修复轮1 重点:
- B-1: 结算屏「再来一局」免费重开 + 30秒分享限频真实拦截
       (修复前: 确认分享后 resetGame 清零 lastShareTime → 限频被绕过;
        修复后: 限频时间戳跨对局保留, 结算屏连续两次进入分享路径第二次被 alert 拦截)
- B-2: 离谱文案内容层 — 抽卡实时生成文案、结算屏显示文案、分享卡显示文案+分数+昵称
"""
import sys, asyncio
from playwright.async_api import async_playwright

URL = "file:///mnt/e/agentguild/docs/evidence/v0.7a/stage2/deliverable/game/index.html"
SHOT_DIR = "/mnt/e/agentguild/docs/evidence/v0.7a/stage2"
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

        async def play_to_result(tag):
            # 从第1局开始连抽5局到结算
            for _ in range(5):
                await click_js("#draw-btn")
            await page.wait_for_timeout(400)
            vis = await page.locator("#result-screen").is_visible()
            await check("%s结算屏出现" % tag, vis)

        await page.goto(URL)
        await page.wait_for_timeout(500)

        title = await page.title()
        await check("title 离谱卡牌", "离谱卡牌" in title, title)
        cards0 = await page.locator("#card-container .card").count()
        await check("初始渲染3张卡", cards0 == 3, cards0)
        round0 = (await page.locator("#round-num").text_content()).strip()
        await check("第1局开始", round0 == "1", round0)

        # ===== B-2: 抽卡实时生成离谱文案 =====
        await click_js("#draw-btn")
        round1 = (await page.locator("#round-num").text_content()).strip()
        await check("抽卡后第2局", round1 == "2", round1)
        msg1 = (await page.locator("#game-msg").text_content()).strip()
        await check("抽卡实时生成离谱文案", "离谱文案" in msg1 and "你抽到了" in msg1, msg1[:70])
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
        await check("结算屏出现(翻车1)", result_visible)
        if result_visible:
            rt = await page.locator("#result-title").text_content()
            await check("结算显示离谱值", "离谱值" in rt, rt)
            copy1 = (await page.locator("#result-copy").text_content()).strip()
            await check("结算屏显示离谱文案", "你抽到了" in copy1 and "×" in copy1, copy1[:70])
            inter_visible = await page.locator("#interstitial-ad").is_visible()
            await check("插屏广告占位显示(第5局)", inter_visible)
            rev_visible = await page.locator("#ad-reverse-btn").is_visible()
            await check("逆袭翻倍按钮出现", rev_visible)
            await page.screenshot(path=SHOT_DIR + "/lipu-mobile.png")

        # ===== B-1: 结算屏「再来一局」免费重开 =====
        restart_visible = await page.locator("#result-restart-btn").is_visible()
        await check("结算屏再来一局按钮可见", restart_visible)
        free_note = (await page.locator("#free-note").text_content()).strip()
        await check("免费游玩显式入口", "免费" in free_note, free_note)
        await click_js("#result-restart-btn")
        game_visible = await page.locator("#game-screen").is_visible()
        await check("再来一局回主屏", game_visible)
        round_r = (await page.locator("#round-num").text_content()).strip()
        await check("再来一局后第1局", round_r == "1", round_r)

        # 再玩一局到结算 (翻车2)
        await play_to_result("再翻车")

        # ===== 分享路径1: 分享成功 (B-2 分享卡内容) =====
        await click_js("#share-btn")
        share_visible = await page.locator("#share-screen").is_visible()
        await check("分享屏出现(第1次进分享路径)", share_visible)
        if share_visible:
            scopy = (await page.locator("#share-copy").text_content()).strip()
            await check("分享卡显示离谱文案", "你抽到了" in scopy and "×" in scopy, scopy[:70])
            snick = (await page.locator("#share-nick").text_content()).strip()
            await check("分享卡显示玩家昵称", len(snick) > 0, snick)
            sscore = (await page.locator("#share-score").text_content()).strip()
            await check("分享卡显示分数", sscore.isdigit() and int(sscore) > 0, sscore)
        await click_js("#confirm-share-btn")
        await page.wait_for_timeout(300)
        game_visible = await page.locator("#game-screen").is_visible()
        await check("分享后回主屏", game_visible)
        round_after = (await page.locator("#round-num").text_content()).strip()
        await check("分享后新一局", round_after == "1", round_after)

        # ===== 限频修复验证: 完成分享后立刻再打到结算, 再次进分享路径必须被拦截 =====
        # (修复前: confirmShare → resetGame 清零 lastShareTime → 此处分享屏直接打开, 限频被绕过)
        await play_to_result("限频场景到结算")
        n_before = len(dialogs)
        await click_js("#share-btn")
        await page.wait_for_timeout(300)
        share_visible2 = await page.locator("#share-screen").is_visible()
        blocked1 = len(dialogs) > n_before
        last_msg = dialogs[-1] if blocked1 else ""
        await check("分享后立即再进分享路径被限频拦截(alert)", blocked1 and "分享太频繁" in last_msg, last_msg[:40])
        await check("限频拦截后仍在结算屏", not share_visible2 and await page.locator("#result-screen").is_visible())

        # ===== 限频验证2: 拦截后再次尝试同样被拦截 (不进分享屏) =====
        n_before2 = len(dialogs)
        await click_js("#share-btn")
        await page.wait_for_timeout(300)
        share_visible3 = await page.locator("#share-screen").is_visible()
        blocked2 = len(dialogs) > n_before2 and "分享太频繁" in dialogs[-1]
        await check("连续第3次进分享路径仍被拦截", blocked2 and not share_visible3, dialogs[-1][:40] if blocked2 else "")

        # ===== 限频验证3 (取消路径, 独立会话): 结算屏「分享→取消→立即再分享」第二次被拦截 =====
        await page.reload()
        await page.wait_for_timeout(500)
        await play_to_result("新会话到结算")
        await click_js("#share-btn")
        share_visible4 = await page.locator("#share-screen").is_visible()
        await check("新会话分享屏出现(第1次)", share_visible4)
        await click_js("#cancel-share-btn")
        result_back = await page.locator("#result-screen").is_visible()
        await check("取消分享回结算屏", result_back)
        n_before3 = len(dialogs)
        await click_js("#share-btn")
        await page.wait_for_timeout(300)
        share_visible5 = await page.locator("#share-screen").is_visible()
        blocked3 = len(dialogs) > n_before3 and "分享太频繁" in dialogs[-1]
        await check("取消后立即再进分享路径被拦截", blocked3 and not share_visible5, dialogs[-1][:40] if blocked3 else "")

        # ===== 收尾检查 =====
        best = await page.evaluate("localStorage.getItem('absurd_best')")
        await check("localStorage 存档", best is not None and int(best) > 0, best)
        await check("无 console 错误", len(console_errors) == 0, console_errors[:3])
        await check("有对话框交互(广告/分享/限频提示)", len(dialogs) >= 5, len(dialogs))

        # 桌面端截图 (1280x900)
        page2 = await browser.new_page(viewport={"width": 1280, "height": 900})
        page2.on("dialog", on_dialog)
        await page2.goto(URL)
        await page2.wait_for_timeout(500)
        for _ in range(5):
            await page2.evaluate("document.querySelector('#draw-btn').click()")
            await page2.wait_for_timeout(300)
        await page2.wait_for_timeout(400)
        await page2.screenshot(path=SHOT_DIR + "/lipu-desktop.png")
        await page2.close()

        await page.screenshot(path="/tmp/lipu-result.png")
        await browser.close()

    fails = [r for r in results if not r[1]]
    print("\n==== %d/%d passed ====" % (len(results) - len(fails), len(results)))
    if fails:
        print("FAILED:", [f[0] for f in fails])
    sys.exit(1 if fails else 0)

asyncio.run(main())
