#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 PVE 管家 fnOS 应用图标（ICON.PNG 90x90 + ICON_256.PNG 256x256）。

源素材：build/icon-source.jpg（用户定稿参考图：白底 PVE 官方 X 图形
+ 右下角飞牛蓝圆角角标 + 白色牛头标志）。仅做 LANCZOS 缩放。
"""

import os
import sys

from PIL import Image


FNOS_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "fnos"))
SOURCE = os.path.join(os.path.dirname(__file__), "icon-source.jpg")


def main() -> int:
    os.makedirs(FNOS_DIR, exist_ok=True)
    src = Image.open(SOURCE).convert("RGB")
    for size, name in ((90, "ICON.PNG"), (256, "ICON_256.PNG")):
        out = os.path.join(FNOS_DIR, name)
        src.resize((size, size), Image.LANCZOS).convert("RGBA").save(out, "PNG")
        print(f"generated {out} ({size}x{size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
