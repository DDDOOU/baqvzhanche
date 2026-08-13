# -*- coding: utf-8 -*-
"""程序化音效合成 — baqvzhanche 战棋 0.5.5
numpy 离线合成 14 个音效到 战棋0.5/assets/audio/ (44100Hz 16bit 单声道 wav)
配方: 振荡器/噪声 x 包络 x 滤波。重跑本脚本即可整体重生成。
"""
import numpy as np
import wave, os, math

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)


# ---------- 基础构件 ----------
def noise(n):
    return np.random.uniform(-1.0, 1.0, n)

def sine(freq, n):
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t)

def sweep(f0, f1, n, curve=1.0):
    """频率从 f0 线性滑到 f1（curve=1 指数感）"""
    t = np.arange(n) / SR
    dur = n / SR
    freq = f0 * (f1 / f0) ** (t / dur) if curve else f0 + (f1 - f0) * t / dur
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase)

def env_exp(n, tau_s):
    """指数衰减包络（tau_s 秒）"""
    t = np.arange(n) / SR
    return np.exp(-t / tau_s)

def env_adsr(n, a=0.005, d=0.05, s=0.6, r=0.1):
    """ADSR 包络（s 为 sustain 比例，r 为释放秒数）"""
    e = np.ones(n)
    na = int(a * SR); nd = int(d * SR); nr = int(r * SR)
    ns = max(n - na - nd - nr, 1)
    if na > 0: e[:na] = np.linspace(0, 1, na)
    if nd > 0: e[na:na+nd] = np.linspace(1, s, nd)
    if nr > 0: e[na+nd+ns:] = np.linspace(s, 0, nr)
    return e

def lowpass(x, cutoff):
    """一阶 IIR 低通"""
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += (1 - a) * (x[i] - acc)
        y[i] = acc
    return y

def mix(*parts, gain=0.85):
    """叠加并归一化"""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    peak = np.max(np.abs(out)) or 1.0
    return out * (gain / peak)

def save(name, data):
    data = np.clip(data, -1.0, 1.0)
    pcm = (data * 32767).astype(np.int16)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name:20s} {len(data)/SR:5.2f}s  {os.path.getsize(path)//1024}KB")


# ---------- 合成 ----------
print("合成音效 ->", OUT)

# 1. UI 点击: 1200Hz 正弦 x 快衰减
save("ui_click.wav", mix(sine(1200, int(0.05*SR)) * env_exp(int(0.05*SR), 0.012), gain=0.7))

# 2. 选中单位: 880->1320Hz 双音确认（五度）
n = int(0.14*SR)
tone1 = sine(880, int(0.07*SR)) * env_exp(int(0.07*SR), 0.02)
tone2 = sine(1320, int(0.07*SR)) * env_exp(int(0.07*SR), 0.02)
sel = np.zeros(n); sel[:len(tone1)] += tone1; sel[len(tone1):] += tone2[:n-len(tone1)]
save("unit_select.wav", mix(sel, gain=0.7))

# 3. 移动下令: 双声脚步（低频噪声拍）
step1 = lowpass(noise(int(0.06*SR)), 400) * env_exp(int(0.06*SR), 0.015)
step2 = lowpass(noise(int(0.06*SR)), 350) * env_exp(int(0.06*SR), 0.015)
mv = np.zeros(int(0.18*SR)); mv[:len(step1)] += step1; mv[int(0.10*SR):int(0.10*SR)+len(step2)] += step2
save("move_order.wav", mix(mv, gain=0.6))

# 4. 步枪/机枪: 高频噪声 burst 三连发
burst = lowpass(noise(int(0.09*SR)), 2500) * env_exp(int(0.09*SR), 0.02)
burst2 = lowpass(noise(int(0.09*SR)), 2200) * env_exp(int(0.09*SR), 0.02)
burst3 = lowpass(noise(int(0.09*SR)), 2000) * env_exp(int(0.09*SR), 0.02)
g = np.zeros(int(0.40*SR))
for i, b in enumerate([burst, burst2, burst3]):
    off = int(i * 0.12 * SR); g[off:off+len(b)] += b
save("gunshot.wav", mix(g, gain=0.75))

# 5. 坦克炮: 低频"砰" + 噪声瞬态
n = int(0.40*SR)
boom = sine(95, n) * env_exp(n, 0.09)
trans = lowpass(noise(int(0.12*SR)), 1500) * env_exp(int(0.12*SR), 0.03)
tf = np.zeros(n); tf[:len(trans)] += trans; tf += boom * 0.8
save("tank_fire.wav", mix(tf, gain=0.9))

# 6. 命中: 短促高频冲击
n = int(0.18*SR)
imp = lowpass(noise(n), 3000) * env_exp(n, 0.035) + sine(220, n) * env_exp(n, 0.05) * 0.5
save("hit.wav", mix(imp, gain=0.8))

# 7. 爆炸: 白噪 x 长衰减 + 低频轰鸣滑降
n = int(1.2*SR)
nz = lowpass(noise(n), 900) * env_exp(n, 0.35)
rumble = sweep(90, 38, n) * env_exp(n, 0.55) * 0.9
crack = lowpass(noise(int(0.05*SR)), 4000) * env_exp(int(0.05*SR), 0.01) * 1.2
ex = np.zeros(n); ex[:len(crack)] += crack; ex += nz + rumble
save("explosion.wav", mix(ex, gain=0.95))

# 8. 士气崩溃: 锯齿下滑 + 噪声尾
n = int(0.9*SR)
saw = 2 * (sweep(200, 80, n) * 0.5 + 0.5) - 1  # 近似锯齿
tail = lowpass(noise(int(0.4*SR)), 600) * env_exp(int(0.4*SR), 0.12)
mb = np.zeros(n); mb += saw * env_exp(n, 0.5) * 0.7; mb[int(0.5*SR):] += tail[:n-int(0.5*SR)]
save("morale_break.wav", mix(mb, gain=0.8))

# 9. 回合计划开始: 方波三连音（低中高）
def square(freq, n, duty=0.5):
    t = np.arange(n) / SR
    return np.sign(np.sin(2*np.pi*freq*t) + 1e-9) * (1 if duty == 0.5 else 0)
def tone(freq, dur, decay=0.05, g=0.5):
    nn = int(dur*SR)
    return square(freq, nn) * env_exp(nn, decay) * g
rp = np.zeros(int(0.5*SR))
for i, f in enumerate([392, 494, 587]):
    off = int(i*0.13*SR); t = tone(f, 0.11); rp[off:off+len(t)] += t
save("round_plan.wav", mix(rp, gain=0.6))

# 10. 演绎开始: 低音鼓点 x2 + 金属叮
n = int(0.5*SR)
drum = lowpass(noise(int(0.25*SR)), 200) * env_exp(int(0.25*SR), 0.06) + sine(65, int(0.25*SR)) * env_exp(int(0.25*SR), 0.08)
re = np.zeros(n); re[:len(drum)] += drum * 0.9
re[int(0.25*SR):int(0.25*SR)+len(drum)] += drum * 0.7
ding = sine(1568, int(0.15*SR)) * env_exp(int(0.15*SR), 0.03) * 0.25
re[int(0.28*SR):int(0.28*SR)+len(ding)] += ding
save("round_exec.wav", mix(re, gain=0.8))

# 11. 卡牌使用: 滑音 400->1200 + 颤音
n = int(0.32*SR)
slide = sweep(400, 1200, n) * env_adsr(n, a=0.01, d=0.1, s=0.3, r=0.08)
trem = (1 + 0.15 * np.sin(2*np.pi*28*np.arange(n)/SR))
save("card_use.wav", mix(slide * trem, gain=0.6))

# 12. 贷款金币: 高频双音快速交替 x4
n = int(0.55*SR)
coin = np.zeros(n)
for i in range(4):
    f = 1000 if i % 2 == 0 else 1500
    off = int(i*0.12*SR); t = sine(f, int(0.09*SR)) * env_exp(int(0.09*SR), 0.03)
    coin[off:off+len(t)] += t * 0.8
save("loan_coin.wav", mix(coin, gain=0.65))

# 13. 胜利: C-E-G 上行和弦
n = int(1.5*SR)
vic = np.zeros(n)
for i, f in enumerate([523.25, 659.25, 783.99]):
    off = int(i*0.18*SR); t = sine(f, int(0.9*SR)) * env_adsr(int(0.9*SR), a=0.02, d=0.15, s=0.7, r=0.25) * 0.35
    vic[off:off+len(t)] += t
vic += np.zeros(n)  # 占位保持结构
high = sine(1046.5, int(0.6*SR)) * env_exp(int(0.6*SR), 0.25) * 0.15
vic[int(0.9*SR):int(0.9*SR)+len(high)] += high
save("victory.wav", mix(vic, gain=0.8))

# 14. 失败: A-E-A 下行
n = int(1.5*SR)
defe = np.zeros(n)
for i, f in enumerate([440.0, 329.63, 220.0]):
    off = int(i*0.22*SR); t = sine(f, int(0.9*SR)) * env_adsr(int(0.9*SR), a=0.02, d=0.15, s=0.6, r=0.3) * 0.35
    defe[off:off+len(t)] += t
save("defeat.wav", mix(defe, gain=0.75))

print("完成。")
