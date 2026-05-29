"""现代渐变背景 + 白色机器人 App 图标（无 PIL 依赖）"""
import struct, zlib, os

BASE = r'c:\Users\lenovo\Desktop\ai-chat-app\android\app\src\main\res'

# 渐变色：深靛蓝 → 紫罗兰（现代 AI 产品主流配色）
TOP_COLOR    = (0x4F, 0x46, 0xE5, 0xFF)  # 靛蓝 #4F46E5
BOTTOM_COLOR = (0x7C, 0x3A, 0xED, 0xFF)  # 紫罗兰 #7C3AED

# 机器人主体：白色
BOT_WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
BOT_SHADOW = (0xE0, 0xDD, 0xF8, 0xFF)  # 淡紫阴影
EYE_DARK = (0x4F, 0x46, 0xE5, 0xFF)     # 靛蓝眼睛
ANTENNA_TIP = (0x7C, 0x3A, 0xED, 0xFF)  # 紫罗兰天线球
ACCENT_LIGHT = (0xC4, 0xB5, 0xFD, 0xFF) # 浅紫点缀


def to_png(w, h, pixels):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            raw += bytes(pixels[y * w + x])
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw))
            + chunk(b'IEND', b''))


def gradient_bg(w, h):
    """垂直渐变背景"""
    p = [(0, 0, 0, 0)] * (w * h)
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(TOP_COLOR[0] + (BOTTOM_COLOR[0] - TOP_COLOR[0]) * t)
        g = int(TOP_COLOR[1] + (BOTTOM_COLOR[1] - TOP_COLOR[1]) * t)
        b = int(TOP_COLOR[2] + (BOTTOM_COLOR[2] - TOP_COLOR[2]) * t)
        c = (r, g, b, 255)
        for x in range(w):
            p[y * w + x] = c
    return p


def blend(c1, c2, alpha):
    """c1 上叠加 c2，alpha 0.0~1.0"""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * alpha) for i in range(4))


def fr(p, w, h, x1, y1, x2, y2, c):
    for y in range(max(0, y1), min(h, y2)):
        for x in range(max(0, x1), min(w, x2)):
            p[y * w + x] = c


def fc(p, w, h, cx, cy, r, c):
    for y in range(max(0, int(cy - r)), min(h, int(cy + r) + 1)):
        for x in range(max(0, int(cx - r)), min(w, int(cx + r) + 1)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r ** 2:
                p[y * w + x] = c


def frr(p, w, h, x1, y1, x2, y2, rr, c):
    for y in range(max(0, y1), min(h, y2)):
        for x in range(max(0, x1), min(w, x2)):
            inside = True
            if x < x1 + rr and y < y1 + rr:
                inside = (x - (x1 + rr)) ** 2 + (y - (y1 + rr)) ** 2 <= rr ** 2
            elif x >= x2 - rr and y < y1 + rr:
                inside = (x - (x2 - rr - 1)) ** 2 + (y - (y1 + rr)) ** 2 <= rr ** 2
            elif x < x1 + rr and y >= y2 - rr:
                inside = (x - (x1 + rr)) ** 2 + (y - (y2 - rr - 1)) ** 2 <= rr ** 2
            elif x >= x2 - rr and y >= y2 - rr:
                inside = (x - (x2 - rr - 1)) ** 2 + (y - (y2 - rr - 1)) ** 2 <= rr ** 2
            if inside:
                p[y * w + x] = c


def draw(w, h, scl=0.78):
    p = gradient_bg(w, h)
    cx, cy = w / 2, h / 2
    s = min(w, h) * scl

    # === 光晕（机器人后方柔光） ===
    glow_r = int(s * 0.32)
    glow_y = int(cy - s * 0.02)
    for y in range(max(0, int(glow_y - glow_r * 1.3)), min(h, int(glow_y + glow_r * 1.3) + 1)):
        for x in range(max(0, int(cx - glow_r * 1.3)), min(w, int(cx + glow_r * 1.3) + 1)):
            dist = ((x - cx) ** 2 + (y - glow_y) ** 2) ** 0.5
            if dist < glow_r * 1.3:
                alpha = max(0, 1 - dist / (glow_r * 1.3)) * 0.18
                p[y * w + x] = blend(p[y * w + x], (255, 255, 255, 255), alpha)

    # === 天线 ===
    aw, ah = int(s * 0.035), int(s * 0.14)
    ay = int(cy - s * 0.22)
    fr(p, w, h, int(cx - aw / 2), ay - ah, int(cx + aw / 2), ay, BOT_WHITE)

    # 天线球（紫罗兰，带光晕）
    tip_r = int(s * 0.05)
    tip_cy = ay - ah - int(s * 0.03)
    fc(p, w, h, cx, tip_cy, int(tip_r * 1.4), blend(ANTENNA_TIP, (255, 255, 255, 255), 0.15))
    fc(p, w, h, cx, tip_cy, tip_r, ANTENNA_TIP)

    # === 耳朵 ===
    ew, eh = int(s * 0.04), int(s * 0.12)
    ey = int(cy - s * 0.02)
    frr(p, w, h, int(cx - s * 0.27 - ew), ey, int(cx - s * 0.27), ey + eh, int(s * 0.015), BOT_WHITE)
    frr(p, w, h, int(cx + s * 0.27), ey, int(cx + s * 0.27 + ew), ey + eh, int(s * 0.015), BOT_WHITE)

    # === 头部 ===
    hw, hh = int(s * 0.26), int(s * 0.21)
    hy = int(cy - s * 0.06)
    rr = int(s * 0.065)
    # 阴影层（向下偏移 1px）
    frr(p, w, h, int(cx - hw), hy + 1, int(cx + hw), hy + hh + 1, rr, BOT_SHADOW)
    # 主体
    frr(p, w, h, int(cx - hw), hy, int(cx + hw), hy + hh, rr, BOT_WHITE)

    # === 脖子 ===
    nw, nh = int(s * 0.065), int(s * 0.04)
    fr(p, w, h, int(cx - nw / 2), hy + hh - 2, int(cx + nw / 2), hy + hh + nh, BOT_WHITE)

    # === 身体 ===
    bw, bh = int(s * 0.20), int(s * 0.17)
    by = hy + hh + nh
    body_rr = int(s * 0.055)
    # 阴影层
    frr(p, w, h, int(cx - bw), by + 1, int(cx + bw), by + bh + 1, body_rr, BOT_SHADOW)
    # 主体
    frr(p, w, h, int(cx - bw), by, int(cx + bw), by + bh, body_rr, BOT_WHITE)

    # === 眼睛 ===
    er = int(s * 0.062)
    eyy = int(hy + hh * 0.36)
    es = int(s * 0.095)
    # 眼白
    fc(p, w, h, cx - es, eyy, er, (255, 255, 255, 255))
    fc(p, w, h, cx + es, eyy, er, (255, 255, 255, 255))
    # 瞳孔（靛蓝色）
    pr = int(s * 0.026)
    fc(p, w, h, cx - es, eyy, pr, EYE_DARK)
    fc(p, w, h, cx + es, eyy, pr, EYE_DARK)
    # 眼睛高光（小白点）
    hl_r = int(s * 0.01)
    fc(p, w, h, cx - es - int(s * 0.015), eyy - int(s * 0.015), hl_r, (255, 255, 255, 255))
    fc(p, w, h, cx + es - int(s * 0.015), eyy - int(s * 0.015), hl_r, (255, 255, 255, 255))

    # === 微笑 ===
    mw = int(s * 0.09)
    my = int(hy + hh * 0.68)
    for dx in [-int(s * 0.035), 0, int(s * 0.035)]:
        dy = int(abs(dx) * 0.25)
        fc(p, w, h, cx + dx, my + dy, int(s * 0.017), ACCENT_LIGHT)

    # === 身体指示灯 ===
    btn_r = int(s * 0.025)
    btn_yy = int(by + bh * 0.38)
    btn_dx = int(s * 0.055)
    fc(p, w, h, cx - btn_dx, btn_yy, btn_r, ACCENT_LIGHT)
    fc(p, w, h, cx, btn_yy, btn_r, EYE_DARK)
    fc(p, w, h, cx + btn_dx, btn_yy, btn_r, ACCENT_LIGHT)

    return p


def save_png(path, w, h, scl=0.78):
    pixels = draw(w, h, scl)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(to_png(w, h, pixels))
    print(f'  {os.path.basename(os.path.dirname(path))}/{os.path.basename(path)} ({w}x{h})')


if __name__ == '__main__':
    legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    print('=== Legacy 图标 ===')
    for d, sz in legacy.items():
        save_png(os.path.join(BASE, f'mipmap-{d}', 'ic_launcher.png'), sz, sz, 0.75)

    fg = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
    print('\n=== Adaptive 前景 ===')
    for d, sz in fg.items():
        save_png(os.path.join(BASE, f'drawable-{d}', 'ic_launcher_foreground.png'), sz, sz, 0.78)

    print('\n所有图标生成完成！')
