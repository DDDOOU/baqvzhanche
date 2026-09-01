#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量生成战棋卡牌立绘 — micuapi gpt-image-2, 走 HTTP 代理
用法: python gen_card_art.py <template|batch|test>
"""
import base64
import json
import os
import sys
import time
import urllib.request

API_KEY = open("D:/micuapi_key.txt", "r").read().strip()
API_URL = "https://www.micuapi.ai/v1/images/generations"
PROXY = "http://127.0.0.1:10808"
OUT_DIR = "D:/Project_code/baqvzhanche/战棋0.5.2/assets/cards"
STYLE_SUFFIX = "Soviet brutalist military trading card art, portrait 8:11, dark olive-drab and charcoal background, heavy grain texture, worn stencil edges, faint red star watermark, distressed metal border with rivets, 1980s Cold War Warsaw Pact propaganda poster aesthetic, rough brush strokes, muted military colors, gritty analog film grain, no text no letters no numbers"

def gen_image(prompt: str, out_path: str, ref_url: str = None) -> bool:
    payload = {
        "model": "gpt-image-2",
        "prompt": prompt,
        "size": "1024x1536",  # 2:3 接近卡牌 8:11
        "response_format": "b64_json",
        "n": 1,
    }
    if ref_url:
        # micuapi 图生图: 传 image 字段 (参考图 URL)
        payload["image"] = ref_url
    # 标准代理: ProxyHandler (req.set_proxy 对 https 不生效导致 403)
    proxy_handler = urllib.request.ProxyHandler({
        "http": PROXY,
        "https": PROXY,
    })
    opener = urllib.request.build_opener(proxy_handler)
    req = urllib.request.Request(API_URL, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + API_KEY)
    # Cloudflare 拦截 urllib 默认 UA (error 1010) — 用浏览器 UA
    req.add_header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")
    data = json.dumps(payload).encode("utf-8")
    try:
        with opener.open(req, data=data, timeout=240) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        b64 = body["data"][0]["b64_json"]
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "wb") as f:
            f.write(base64.b64decode(b64))
        print(f"[OK] {os.path.basename(out_path)}")
        return True
    except Exception as e:
        print(f"[FAIL] {os.path.basename(out_path)}: {e}")
        return False


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "test"
    os.makedirs(OUT_DIR, exist_ok=True)

    if mode == "test":
        # 单张测试: 母版模板
        gen_image(
            f"Empty military card template with blank central area for subject art, top red banner strip, bottom description strip. {STYLE_SUFFIX}",
            os.path.join(OUT_DIR, "template_test.png"))

    elif mode == "template":
        # 母版: 生成后作为后续参考图
        gen_image(
            f"A Soviet red star emblem over a tactical battlefield map with grid lines, compass and unit markers, dramatic low-angle. {STYLE_SUFFIX}",
            os.path.join(OUT_DIR, "template.png"))

    elif mode == "batch":
        # 12 张正式卡 + 1 张乱码 = 13 张
        cards = [
            ("coordinate_prediction", "Soviet artillery observer with binoculars and radio, pointing at coordinates on a tactical map, red arrow target marker"),
            ("blind_fire_barrage", "Soviet BM-21 Grad rocket launcher firing a salvo of rockets into the distance, smoke trails, night sky"),
            ("smoke_screen", "Smoke grenades deployed on a battlefield, thick white smoke clouds rolling across muddy terrain"),
            ("call_artillery", "Soviet 2S1 Gvozdika self-propelled howitzer firing, muzzle flash, shell casings, artillery battery in background"),
            ("fortify_position", "Sandbag bunker with concrete embrasure, soldiers reinforcing defensive position, barbed wire"),
            ("emi_countermeasure", "Soviet electronic warfare vehicle with antenna arrays emitting interference waves, radio mast, signal jamming visual effect"),
            ("radio_silence", "Soviet radio operator with headset pressing hand on radio, finger to lips for silence, dim bunker"),
            ("reserve_deployment", "T-72B tanks and motor rifle infantry column rolling out from hidden reserve positions at dawn"),
            ("sapper_mines", "Soviet sapper engineer planting anti-tank mines in the dirt, mine casing in hand, warning stakes"),
            ("sacrifice_charge", "Soviet infantry squad charging forward under fire, soldier leading the assault with rifle bayonet, explosions behind"),
            ("power_cut", "Electrical power lines and transformer station short-circuiting with sparks, darkness spreading over city block"),
            ("false_report", "Soviet intelligence officer stamping a fake report document, radio transmitter and decoy markers on map table, dim lamp"),
            ("scrambled", "Soviet military radio and documents destroyed by electromagnetic interference, static noise, cracked screen, glitch effect"),
        ]
        # 母版参考图 (需先生成 template)
        ref_url = None
        template_path = os.path.join(OUT_DIR, "template.png")
        if os.path.exists(template_path):
            # 本地文件 → 需要可访问 URL; micuapi 图生图支持本地 b64? 先不用参考, 靠风格后缀锁风格
            print("[batch] 本地 template 无法作 URL 参考, 依赖 STYLE_SUFFIX 锁风格")
        for cid, subject in cards:
            prompt = f"{subject}. {STYLE_SUFFIX}"
            gen_image(prompt, os.path.join(OUT_DIR, f"{cid}.png"))


if __name__ == "__main__":
    main()
