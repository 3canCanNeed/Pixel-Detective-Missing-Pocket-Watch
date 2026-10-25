# -*- coding: utf-8 -*-
"""gen_assets.py -- 生成 16x16 像素贴图（全部程序生成，零外部素材）"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
os.makedirs(OUT, exist_ok=True)
T = 16


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))
    print("asset:", name + ".png")


def noise_tile(base, speckles, n=26, seed=1):
    import random
    r = random.Random(seed)
    img = Image.new("RGBA", (T, T), base)
    dr = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = r.randint(0, T - 1), r.randint(0, T - 1)
        c = r.choice(speckles)
        dr.point((x, y), c)
    return img


# ---------- 地图块 ----------
road = noise_tile((52, 56, 66, 255), [(60, 64, 74, 255), (44, 48, 58, 255), (66, 70, 82, 255)], 40, 1)
save(road, "tile_road")

sidewalk = noise_tile((96, 100, 112, 255), [(86, 90, 102, 255), (106, 110, 122, 255)], 30, 2)
d = ImageDraw.Draw(sidewalk)
d.line([(0, 8), (16, 8)], fill=(80, 84, 96, 255))
save(sidewalk, "tile_sidewalk")

wall = Image.new("RGBA", (T, T), (94, 62, 48, 255))
d = ImageDraw.Draw(wall)
for y in range(0, T, 4):
    d.line([(0, y), (16, y)], fill=(70, 46, 36, 255))
    off = 0 if (y // 4) % 2 == 0 else 8
    for bx in range(off, T, 16):
        d.line([(bx, y), (bx, y + 4)], fill=(70, 46, 36, 255))
d.point((3, 2), (120, 84, 64, 255)); d.point((11, 9), (120, 84, 64, 255))
save(wall, "tile_wall")

floor = Image.new("RGBA", (T, T), (122, 90, 58, 255))
d = ImageDraw.Draw(floor)
for y in range(0, T, 4):
    d.line([(0, y), (16, y)], fill=(100, 72, 46, 255))
d.line([(8, 0), (8, 4)], fill=(100, 72, 46, 255))
d.line([(4, 8), (4, 12)], fill=(100, 72, 46, 255))
save(floor, "tile_floor")

counter = Image.new("RGBA", (T, T), (138, 106, 66, 255))
d = ImageDraw.Draw(counter)
d.rectangle([0, 0, 15, 2], fill=(166, 132, 84, 255))
d.line([(0, 15), (16, 15)], fill=(104, 78, 48, 255))
d.line([(0, 7), (16, 7)], fill=(120, 92, 56, 255))
save(counter, "tile_counter")

door = Image.new("RGBA", (T, T), (74, 48, 32, 255))
d = ImageDraw.Draw(door)
d.rectangle([2, 1, 13, 15], outline=(40, 26, 18, 255))
d.rectangle([4, 3, 11, 8], fill=(94, 62, 40, 255))
d.ellipse([11, 8, 13, 10], fill=(210, 180, 90, 255))
save(door, "tile_door")

puddle = Image.new("RGBA", (T, T), (0, 0, 0, 0))
d = ImageDraw.Draw(puddle)
d.ellipse([1, 4, 15, 13], fill=(38, 62, 92, 255))
d.ellipse([3, 5, 9, 8], fill=(70, 104, 146, 255))
save(puddle, "tile_puddle")

grass = noise_tile((52, 84, 52, 255), [(62, 98, 60, 255), (44, 74, 46, 255), (70, 110, 66, 255)], 36, 3)
save(grass, "tile_grass")

# ---------- 角色模板 ----------
def sprite(rows, palette, name):
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            dr.point((x, y), palette[ch])
    save(img, name)
    return img


DETECT_DOWN = [
    "................",
    ".....hhhhhh.....",
    "....hhhhhhhh....",
    "...hhhhhhhhhh...",
    "..hhhhhhhhhhhh..",
    "....ffffffff....",
    "....fEfffEff....",
    "....ffffffff....",
    "...cccccccccc...",
    "..cCcccccccCc...",
    "..cCcccccccc.c..",
    "..s.cccccccc.s..",
    "....cccccccc....",
    "....ccc..ccc....",
    "....pp....pp....",
    "....bb....bb....",
]
PC = {"h": (40, 40, 58, 255), "f": (232, 184, 138, 255), "E": (16, 16, 32, 255),
      "c": (58, 74, 106, 255), "C": (80, 98, 138, 255), "s": (58, 74, 106, 255),
      "p": (44, 44, 58, 255), "b": (28, 28, 38, 255)}
sprite(DETECT_DOWN, PC, "player_down")

DETECT_UP = [r.replace("f", "h").replace("E", "h") if 4 <= i <= 6 else r
             for i, r in enumerate(DETECT_DOWN)]
sprite(DETECT_UP, PC, "player_up")

DETECT_SIDE = [
    "................",
    ".....hhhhhh.....",
    "....hhhhhhhh....",
    "...hhhhhhhhhh...",
    "..hhhhhhhhhhhh..",
    "......ffffff....",
    "......fEffff....",
    "......ffffff....",
    ".....cccccccc...",
    ".....cccccccC...",
    ".....cccccccC...",
    ".....cccccc.s...",
    ".....cccccc.....",
    ".....ccc.ccc....",
    ".....pp..pp.....",
    ".....bb..bb.....",
]
sprite(DETECT_SIDE, PC, "player_side")

# NPC（统一朝下）
sprite([
    "................",
    ".....gggggg.....",
    "....gggggggg....",
    "...gggggggggg...",
    "....ffffffff....",
    "....fEffffEf....",
    "....ffffffff....",
    "...aaaaaaaaaa...",
    "..aaaaaaaaaaaa..",
    "..a.aaaaaaaa.a..",
    "....aaaaaaaa....",
    "....aaaaaaaa....",
    "....aaa..aaa....",
    "....aaa..aaa....",
    "....bbb..bbb....",
    "................",
], {"g": (150, 150, 150, 255), "f": (226, 178, 134, 255), "E": (20, 20, 34, 255),
    "a": (138, 74, 74, 255), "b": (40, 36, 40, 255)}, "npc_wang")

sprite([
    "................",
    ".....cccccc.....",
    "....cccccccc....",
    "....cccccccc....",
    "....cccccccc....",
    "....ffffffff....",
    "....fEffffEf....",
    "....ffffffff....",
    "...vvvvvvvvvv...",
    "..vvvvvvvvvvvv..",
    "..v.vvvvvvvv.v..",
    "....vvvvvvvv....",
    "....vvv..vvv....",
    "....ddd..ddd....",
    "....bbb..bbb....",
    "................",
], {"c": (42, 106, 58, 255), "f": (232, 184, 138, 255), "E": (20, 20, 34, 255),
    "v": (70, 90, 70, 255), "d": (60, 60, 74, 255), "b": (30, 30, 30, 255)}, "npc_chen")

sprite([
    "................",
    "....hhhhhhhh....",
    "...hhhhhhhhhh...",
    "...hhhhhhhhhh...",
    "....hggggggh....",
    "....fEffffEf....",
    "....ffffffff....",
    "...aaaaaaaaaa...",
    "..aaaaaaaaaaaa..",
    "..a.aaaaaaaa.a..",
    "....aaaaaaaa....",
    "....aaaaaaaa....",
    "....aaa..aaa....",
    "....aaa..aaa....",
    "....bbb..bbb....",
    "................",
], {"h": (90, 90, 96, 255), "g": (200, 200, 205, 255), "f": (222, 172, 130, 255),
    "E": (20, 20, 34, 255), "a": (86, 66, 48, 255), "b": (34, 30, 28, 255)}, "npc_zhou")

sprite([
    "................",
    "....dddddddd....",
    "...dddddddddd...",
    "....ffffffff....",
    "....fEffffEf....",
    "....ffffffff....",
    "...dddddddddd...",
    "..dddddddddddd..",
    "..d.dddddddd.d..",
    "....dddddddd....",
    "....dddddddd....",
    "....ddd..ddd....",
    "....ddd..ddd....",
    "....bbb..bbb....",
    "................",
    "................",
], {"d": (74, 74, 96, 255), "f": (226, 178, 134, 255), "E": (20, 20, 34, 255),
    "b": (30, 30, 34, 255)}, "npc_li")

# 线索闪光
spark = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
d = ImageDraw.Draw(spark)
d.line([(5, 0), (5, 9)], fill=(255, 224, 110, 255))
d.line([(0, 5), (9, 5)], fill=(255, 224, 110, 255))
d.line([(2, 2), (7, 7)], fill=(255, 200, 60, 160))
d.line([(2, 7), (7, 2)], fill=(255, 200, 60, 160))
save(spark, "sparkle")

print("ALL_ASSETS_DONE:", len(os.listdir(OUT)), "files")
