"""生成 AI Chat App 图标：浅色蓝调 Chatbox 风格"""
from PIL import Image, ImageDraw, ImageFont
import math, os

SIZE = 1024
img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# 圆角裁剪
r = 180
for x in range(SIZE):
    for y in range(SIZE):
        cx = x if x < SIZE // 2 else SIZE - 1 - x
        cy = y if y < SIZE // 2 else SIZE - 1 - y
        d = math.sqrt((max(0, r - cx)) ** 2 + (max(0, r - cy)) ** 2)
        if d > r:
            img.putpixel((x, y), (0, 0, 0, 0))

# 渐变底色：浅蓝到蓝白
for y in range(SIZE):
    for x in range(SIZE):
        if img.getpixel((x, y))[3] == 0:
            continue
        ratio = y / SIZE
        rr = int(74 + ratio * 50)
        rg = int(144 + ratio * 30)
        rb = int(217 - ratio * 40)
        img.putpixel((x, y), (rr, rg, rb, 255))

# 中心 AI 文字 (白色)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 380)
except Exception:
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 380)

text = "AI"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]

# 白色文字
txt_img = Image.new('RGBA', (tw + 40, th + 40), (0, 0, 0, 0))
txt_draw = ImageDraw.Draw(txt_img)
txt_draw.text((20, 20), text, font=font, fill=(255, 255, 255, 255))

tx = (SIZE - tw - 40) // 2
ty = (SIZE - th - 40) // 2
img.paste(txt_img, (tx, ty), txt_img)

out = os.path.join(os.path.dirname(__file__), 'icon_src.png')
img.save(out)
print(f'Icon saved to {out}')
