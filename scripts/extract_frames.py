"""WebP 动图拆帧 → PNG 序列，用于弗糯糯电子宠物皮肤"""
from PIL import Image
import os

SKINS_DIR = r"c:\Users\lenovo\Desktop\ai-chat-app\assets\pet_skins\funuonuo"
SOURCE_DIR = r"c:\Users\lenovo\Desktop\图片"

MAPPINGS = [
    ("douyin_emoticon.awebp", "idle"),
    ("funuonuo_02.awebp",     "hungry"),
    ("funuonuo_03.awebp",     "talking"),
    ("funuonuo_04.awebp",     "sleeping"),
]

for filename, state in MAPPINGS:
    src = os.path.join(SOURCE_DIR, filename)
    dst_dir = os.path.join(SKINS_DIR, state)

    im = Image.open(src)
    n = im.n_frames
    print(f"{filename} → {state}/ ({n} frames)")

    for i in range(n):
        im.seek(i)
        # Convert RGBA to avoid palette issues on export
        frame = im.convert("RGBA")
        out = os.path.join(dst_dir, f"frame_{i:02d}.png")
        frame.save(out, "PNG")

    im.close()

print("\nDone. Frame counts:")
for state in ["idle", "hungry", "talking", "sleeping"]:
    d = os.path.join(SKINS_DIR, state)
    count = len([f for f in os.listdir(d) if f.endswith(".png")])
    print(f"  {state}: {count} frames")
