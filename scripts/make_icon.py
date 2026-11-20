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

# Gold coins: a money mark for any currency (no ₹ or $). Thin and slightly offset so they read as
# coins, not poker chips (chips are thick, aligned and striped).
w, h, thick = 210, 62, 16
EDGE, FACE, RIM = "#B8860B", "#F4C430", "#FFE38A"
for base, cx in [(400, 506), (378, 520), (356, 500), (334, 514)]:  # bottom coin first
    top_y = base - thick
    d.rectangle((cx - w // 2, top_y + h // 2, cx + w // 2, base + h // 2), fill=EDGE)
    d.ellipse((cx - w // 2, base, cx + w // 2, base + h), fill=EDGE)                 # coin edge
    d.ellipse((cx - w // 2, top_y, cx + w // 2, top_y + h), fill=FACE)              # coin face
cx, face = 514, 334 - thick  # top coin: raised rim like a real coin
d.ellipse((cx - w // 2 + 22, face + 9, cx + w // 2 - 22, face + h - 9), outline=RIM, width=7)
# A small sparkle so it reads as shiny metal.
sx, sy, a = 650, 250, 34
d.polygon([(sx, sy - a), (sx + 9, sy - 9), (sx + a, sy), (sx + 9, sy + 9), (sx, sy + a), (sx - 9, sy + 9),
           (sx - a, sy), (sx - 9, sy - 9)], fill="#F4C430")

# Ledger lines.
for y, w in [(510, 300), (590, 220), (670, 260)]:
    d.rounded_rectangle((left + 62, y, left + 62 + w, y + 30), radius=15, fill="#C7C7CC")

out.parent.mkdir(parents=True, exist_ok=True)
img.save(out)
print(out)
