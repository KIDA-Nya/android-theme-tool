#!/usr/bin/env python3
"""check_theme.py —— 应用前体检一个 ColorOS 主题包。

检查项
------
1. 是否是 ColorOS ROM 主题包（根级 themeInfo.xml）
2. EditorVersion 是否与设备 ro.oplus.theme.version 一致
3. 声明（<packageInfo>）与 zip 实际条目是否对应 —— 找出「有内容但没声明」的模块
4. 哪些模块声明了但 zip 里没有（应用时日志会打印 null，通常无害）
5. 是否含锁屏资源 / 锁屏预览图

用法
----
    python check_theme.py <theme.theme> [--device-version 16000]

退出码: 0 无问题 / 2 有需要注意的问题 / 1 参数错误 / 3 不是主题包
"""
import argparse
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

SKIP_EXACT = {'themeInfo.xml', 'themeinfo.xml'}
SKIP_PREFIX = ('picture/', 'previews/', 'descriptions/', 'resources/')
VER_RE = re.compile(r'^(.*)_(\d{2,3})$')
IMAGE_EXT = ('.jpg', '.jpeg', '.png', '.webp')


def base_and_version(name):
    m = VER_RE.match(name)
    if m:
        return m.group(1), m.group(2)
    return name, '001'


def main():
    ap = argparse.ArgumentParser(description='体检 ColorOS 主题包')
    ap.add_argument('theme', help='.theme 文件路径')
    ap.add_argument('--device-version', default=None,
                    help='设备 ro.oplus.theme.version（用于比对 EditorVersion）')
    args = ap.parse_args()

    path = args.theme
    if not os.path.isfile(path):
        sys.stderr.write('找不到文件: %s\n' % path)
        return 1

    try:
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if not n.endswith('/')]
            if 'themeInfo.xml' not in names:
                sys.stderr.write('不是 ColorOS 主题包（缺少根级 themeInfo.xml）\n')
                return 3
            xml = z.read('themeInfo.xml').decode('utf-8')
            sizes = {n: z.getinfo(n).file_size for n in names}
    except zipfile.BadZipFile:
        sys.stderr.write('不是有效的 zip: %s\n' % path)
        return 1

    root = ET.fromstring(xml)

    def text(tag):
        node = root.find(tag)
        return (node.text or '').strip() if node is not None else ''

    print('文件: %s  (%s bytes, %d 条目)' % (os.path.basename(path), format(os.path.getsize(path), ','), len(names)))
    for key in ('Summary', 'Author', 'UUID', 'EditorVersion', 'VersionCode', 'disableLockPictorial'):
        val = text(key)
        if val:
            print('  %-22s %s' % (key, val))

    problems = []

    # EditorVersion 比对
    editor = text('EditorVersion')
    dev = args.device_version
    if dev:
        if editor == dev:
            print('  EditorVersion 比对   一致（%s）' % dev)
        else:
            print('  EditorVersion 比对   不一致：主题 %s / 设备 %s' % (editor or '(空)', dev))
            problems.append('EditorVersion 与设备不匹配，应用会被 ThemeOSVersion 检查中止')

    # 声明 vs 实际
    declared = {}
    holder = root.find('packageInfo')
    if holder is not None:
        for node in holder.findall('package'):
            name = node.get('name')
            if name:
                declared[name] = [v.strip() for v in (node.get('version') or '001').split(',') if v.strip()]

    present = []
    for n in names:
        if n in SKIP_EXACT or n.startswith(SKIP_PREFIX):
            continue
        present.append(n)

    present_bases = {base_and_version(n)[0] for n in present}

    undeclared = [n for n in present if base_and_version(n)[0] not in declared]
    missing_files = [k for k in declared if k not in present_bases]

    print('')
    print('声明 %d 项 / 实际模块 %d 项' % (len(declared), len(present_bases)))

    if undeclared:
        print('')
        print('⚠ 有内容但未声明（应用时会被跳过）：')
        for n in undeclared:
            print('    %-36s %10s B' % (n, format(sizes.get(n, 0), ',')))
        problems.append('%d 个模块未声明，需先运行 theme_align.py 对齐' % len(undeclared))

    if missing_files:
        print('')
        print('声明了但 zip 里没有（应用日志会显示 null，通常无害）：')
        for k in missing_files:
            print('    %s' % k)

    # 锁屏资源
    lock_assets = [n for n in names if re.search(r'(lock|keyguard|aod)', n, re.I)]
    print('')
    if lock_assets:
        print('锁屏相关条目:')
        for n in lock_assets[:8]:
            print('    %-40s %10s B' % (n, format(sizes.get(n, 0), ',')))
    else:
        print('锁屏相关条目: 无（只能换锁屏壁纸，样式仍是系统默认）')

    if text('disableLockPictorial'):
        print('  disableLockPictorial = %s' % text('disableLockPictorial'))

    print('')
    if problems:
        for p in problems:
            print('[!] %s' % p)
        return 2
    print('[OK] 未发现问题')
    return 0


if __name__ == '__main__':
    sys.exit(main())
