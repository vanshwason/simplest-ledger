"""Draws the app icon (receipt + coin) at 1024x1024. Run: python scripts/make_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
out = Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
img = Image.new("RGB", (S, S), "#1C1C1E")  # full-bleed square: iOS adds the rounded mask
d = ImageDraw.Draw(img)

# Receipt strip with a zigzag torn bottom.
left, right, top, bottom, tooth = 300, 724, 150, 830, 53
points = [(left, top), (right, top), (right, bottom)]
x, down = right, False
while x > left:
    x = max(left, x - tooth)
    points.append((x, bottom + (0 if down else 46)))
    down = not down
points.append((left, bottom))
d.polygon(points, fill="#FFFFFF")

# Stack of coins: a money mark that reads for any currency (no ₹ or $).
cx, w, h, thick = S // 2, 230, 70, 34
for base in [380, 340, 300]:  # bottom coin first, so upper coins overlap it
    top_y = base - thick
    d.rectangle((cx - w // 2, top_y + h // 2, cx + w // 2, base + h // 2), fill="#00876A")
    d.ellipse((cx - w // 2, base, cx + w // 2, base + h), fill="#00876A")       # coin edge
    d.ellipse((cx - w // 2, top_y, cx + w // 2, top_y + h), fill="#00A884")     # coin face
face = 300 - thick  # top coin's face
d.ellipse((cx - w // 2 + 34, face + 14, cx + w // 2 - 34, face + h - 14), outline="#7FE0C4", width=8)

# Ledger lines.
for y, w in [(510, 300), (590, 220), (670, 260)]:
    d.rounded_rectangle((left + 62, y, left + 62 + w, y + 30), radius=15, fill="#C7C7CC")

out.parent.mkdir(parents=True, exist_ok=True)
img.save(out)
print(out)
