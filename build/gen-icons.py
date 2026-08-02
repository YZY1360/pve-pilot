#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 PVE 管家 fnOS 应用图标（ICON.PNG 90x90 + ICON_256.PNG 256x256）。

设计：PVE 品牌橙（#E57000）圆角底 + 白色粗体 "PVE"，下方一条白色"数据线"
寓意"透传/管道"。仅使用 PIL 标准库字体，方便在任意开发机复现。
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont


FNOS_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "fnos"))
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

ORANGE_TOP = (255, 138, 30)
ORANGE_BOTTOM = (229, 112, 0)
WHITE = (255, 255, 255, 255)


def rounded_mask(size: int, radius: int) -> Image.Image:
    """生成圆角透明度蒙版（边缘 1px 抗锯齿）。"""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # 垂直渐变底色
    grad = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        r = round(ORANGE_TOP[0] + (ORANGE_BOTTOM[0] - ORANGE_TOP[0]) * t)
        g = round(ORANGE_TOP[1] + (ORANGE_BOTTOM[1] - ORANGE_TOP[1]) * t)
        b = round(ORANGE_TOP[2] + (ORANGE_BOTTOM[2] - ORANGE_TOP[2]) * t)
        grad.putpixel((0, y), (r, g, b, 255))
    bg = grad.resize((size, size))
    img.paste(bg, (0, 0), rounded_mask(size, max(6, size // 8)))

    draw = ImageDraw.Draw(img)
    font_size = int(size * 0.52)
    font = ImageFont.truetype(FONT_PATH, font_size)
    text = "PVE"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (size - tw) / 2 - bbox[0]
    y = size * 0.10 - bbox[1]
    draw.text((x, y), text, font=font, fill=WHITE)

    # 底部"管道/数据线"装饰：圆角横条 + 圆点
    bar_w = int(size * 0.46)
    bar_h = max(3, int(size * 0.055))
    bar_x = (size - bar_w) / 2
    bar_y = size * 0.76
    draw.rounded_rectangle(
        (bar_x, bar_y, bar_x + bar_w, bar_y + bar_h),
        radius=bar_h // 2,
        fill=WHITE,
    )
    dot_r = max(2, int(size * 0.035))
    dot_x = size / 2
    dot_y = bar_y + bar_h / 2
    draw.ellipse(
        (dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r),
        fill=ORANGE_BOTTOM,
    )
    return img


def main() -> int:
    os.makedirs(FNOS_DIR, exist_ok=True)
    for size, name in ((90, "ICON.PNG"), (256, "ICON_256.PNG")):
        out = os.path.join(FNOS_DIR, name)
        draw_icon(size).save(out, "PNG")
        print(f"generated {out} ({size}x{size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
