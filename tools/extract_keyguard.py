#!/usr/bin/env python3
"""从 .theme 中提取锁屏壁纸。

ColorOS 主题包的 `wallpaper` 条目本身是个内嵌 zip，通常包含：
    res/drawable-xxhdpi/oppo_default_keyguard_wallpaper.jpg   ← 锁屏
    res/drawable-xxhdpi/oppo_default_wallpaper.jpg            ← 桌面

OS12 应用路径只把桌面那张设进系统，锁屏那张不会被使用，所以需要单独取出来。

用法:
    python extract_keyguard.py <theme.theme> <out_dir>

成功时在 stdout 打印提取出的文件绝对路径。
退出码: 0 成功 / 2 主题里没有可用图片 / 3 不是 ColorOS 主题包 / 1 参数错误
"""
import io
import os
import sys
import zipfile

IMG_EXT = ('.jpg', '.jpeg', '.png', '.webp')


def find_image(zf):
    """优先 keyguard/lock 命名的图片，否则退而求其次取第一张图。"""
    names = [n for n in zf.namelist() if not n.endswith('/')]
    images = [n for n in names if n.lower().endswith(IMG_EXT)]
    if not images:
        return None
    for n in images:
        low = n.lower()
        if 'keyguard' in low or 'lock' in low:
            return n
    return images[0]


def main(argv):
    if len(argv) != 3:
        sys.stderr.write('用法: python extract_keyguard.py <theme.theme> <out_dir>\n')
        return 1

    src, outdir = argv[1], argv[2]
    if not os.path.isfile(src):
        sys.stderr.write('找不到主题文件: %s\n' % src)
        return 1

    with zipfile.ZipFile(src) as theme:
        if 'themeInfo.xml' not in theme.namelist():
            sys.stderr.write('不是 ColorOS 主题包（缺少 themeInfo.xml）: %s\n' % src)
            return 3
        if 'wallpaper' not in theme.namelist():
            sys.stderr.write('该主题没有 wallpaper 条目: %s\n' % src)
            return 2
        inner_bytes = theme.read('wallpaper')

    try:
        inner = zipfile.ZipFile(io.BytesIO(inner_bytes))
    except zipfile.BadZipFile:
        sys.stderr.write('wallpaper 条目不是有效的 zip\n')
        return 2

    with inner:
        pick = find_image(inner)
        if not pick:
            sys.stderr.write('wallpaper 里没有图片\n')
            return 2
        data = inner.read(pick)

    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, os.path.basename(pick))
    with open(out, 'wb') as f:
        f.write(data)

    print(os.path.abspath(out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
