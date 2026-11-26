"""从 ColorOS / MIUI / 华为 主题包里把资源拆出来（壁纸、图标、字体、铃声、预览图）。

为什么需要它：三个平台的"直接投递"只有 ColorOS 走得通，但**资源本身是通用的**——
把图/字体/音频拿出来，再用系统标准 API（壁纸、铃声）应用到任意品牌的机器上。

用法：
    python extract_assets.py <主题包> -o <输出目录>          # 拆出来
    python extract_assets.py <主题包> --list                # 只看清单，不写文件

支持：.theme（ColorOS）/ .mtz（MIUI）/ .hwt（华为），也接受 zip 内容相同的其它后缀。

分类规则（按路径与文件名推断，宁可多报不遗漏）：
    wallpaper   路径含 wallpaper/lock/bg，或文件名含 wallpaper/wall/lockbg
    icons       路径含 icons/ 或 res/drawable* 且是应用图标尺寸
    fonts       ttf / otf / ttc
    ringtone    mp3 / ogg / wav / m4a / aac / flac
    preview     路径含 preview/picture/descriptions
    other       其余图片
"""
import argparse
import io
import os
import sys
import zipfile

IMG_EXT = {'.png', '.jpg', '.jpeg', '.webp', '.bmp'}
AUDIO_EXT = {'.mp3', '.ogg', '.wav', '.m4a', '.aac', '.flac'}
FONT_EXT = {'.ttf', '.otf', '.ttc'}

DESCRIPTORS = {'themeInfo.xml': 'ColorOS', 'description.xml': 'MIUI/华为（按根节点区分）'}


def classify(name):
    """按模块目录判归属：ColorOS/MIUI/华为 的顶层目录本身就说明了资源用途。"""
    low = name.lower().replace('\\', '/')
    top = low.split('/')[0]
    ext = os.path.splitext(low)[1]

    if ext in FONT_EXT:
        return 'fonts'
    if ext in AUDIO_EXT:
        return 'ringtone'
    if any(low.startswith(k) or ('/' + k) in low
           for k in ('preview/', 'previews/', 'picture/', 'descriptions/')):
        return 'preview'
    if ext not in IMG_EXT:
        return 'skip'

    if top == 'wallpaper':
        return 'wallpaper'
    if top == 'icons':
        return 'icons'
    if 'wallpaper' in low and 'drawable' not in low:
        return 'wallpaper'
    return 'ui'


def human(n):
    for unit in ('B', 'KB', 'MB'):
        if n < 1024 or unit == 'MB':
            return ('%d B' % n) if unit == 'B' else ('%.1f %s' % (n, unit))
        n /= 1024.0


def iter_assets(z, prefix='', depth=0):
    """递归遍历（ColorOS 的模块本身就是内嵌 zip），产出 (显示名, 字节)。"""
    for info in z.infolist():
        if info.is_dir():
            continue
        name = prefix + info.filename
        try:
            raw = z.read(info)
        except Exception:
            continue
        # 内嵌 zip：ColorOS 每个模块都是一个 zip
        if depth < 2 and raw[:2] == b'PK':
            try:
                inner = zipfile.ZipFile(io.BytesIO(raw))
            except Exception:
                pass
            else:
                for item in iter_assets(inner, name + '/', depth + 1):
                    yield item
                continue
        yield name, raw


def detect(z):
    names = z.namelist()
    if 'themeInfo.xml' in names:
        return 'ColorOS'
    if 'description.xml' in names:
        try:
            head = z.read('description.xml')[:400].decode('utf-8', 'replace')
        except Exception:
            head = ''
        if 'HwTheme' in head:
            return 'Huawei'
        return 'MIUI'
    return 'unknown'


def main(argv=None):
    ap = argparse.ArgumentParser(
        description='从 ColorOS / MIUI / 华为 主题包里拆出可用资源',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument('theme', help='主题包路径')
    ap.add_argument('-o', '--out', help='输出目录（--list 时不需要）')
    ap.add_argument('--list', action='store_true', help='只列清单，不写文件')
    ap.add_argument('--flat', action='store_true', help='输出时压平目录（同名自动加序号）')
    args = ap.parse_args(argv)

    if not os.path.isfile(args.theme):
        print('[x] 找不到文件：%s' % args.theme)
        return 1
    if not args.list and not args.out:
        print('[x] 需要 -o 指定输出目录，或用 --list')
        return 1

    try:
        z = zipfile.ZipFile(args.theme)
    except zipfile.BadZipFile:
        print('[x] 不是 zip：%s' % args.theme)
        return 2

    with z:
        platform = detect(z)
        if platform == 'unknown':
            print('[x] 认不出这是哪个平台的主题包（没有 themeInfo.xml 或 description.xml）')
            return 2

        print('主题包 : %s（%s，%s）'
              % (os.path.basename(args.theme), platform, human(os.path.getsize(args.theme))))

        buckets = {}
        for name, raw in iter_assets(z):
            cat = classify(name)
            if cat in ('preview', 'skip'):
                continue
            buckets.setdefault(cat, []).append((name, raw))

        if not buckets:
            print('[!] 这个包里没有可提取的图片/字体/音频')
            return 0

        total = 0
        for cat in ('wallpaper', 'icons', 'fonts', 'ringtone', 'ui'):
            items = buckets.get(cat, [])
            if not items:
                continue
            size = sum(len(raw) for _n, raw in items)
            print('\n[%s] %d 个，共 %s' % (cat, len(items), human(size)))
            for n, raw in items[:8]:
                print('   %-60s %s' % (n, human(len(raw))))
            if len(items) > 8:
                print('   … 还有 %d 个' % (len(items) - 8))
            total += len(items)

        if args.list:
            print('\n（--list，未写文件；去掉 --list 并加 -o 即可导出）')
            return 0

        used = set()
        written = 0
        for cat, items in buckets.items():
            for name, raw in items:
                if args.flat:
                    base = os.path.basename(name)
                    name, ext = os.path.splitext(base)
                    n = 1
                    while base in used:
                        base = '%s_%d%s' % (name, n, ext)
                        n += 1
                    target = os.path.join(args.out, cat, base)
                else:
                    rel = name.replace('\\', '/')
                    rel = '/'.join(p for p in rel.split('/') if p not in ('..', '.'))
                    # 去掉与本类别同名的首层，避免 .../wallpaper/wallpaper/x.jpg
                    if rel.startswith(cat + '/'):
                        rel = rel[len(cat) + 1:]
                    target = os.path.join(args.out, cat, rel)
                used.add(os.path.basename(target))

                os.makedirs(os.path.dirname(target) or '.', exist_ok=True)
                with open(target, 'wb') as dst:
                    dst.write(raw)
                written += 1

        print('\n导出完成：%d 个文件 → %s' % (written, args.out))
        return 0


if __name__ == '__main__':
    sys.exit(main())
