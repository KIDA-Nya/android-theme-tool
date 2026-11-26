"""校验 theme_mix.py 的输出（与 mk_mix_fixtures.py 配套）。

用法: python check_mix.py <mixed.theme>
退出码: 0 全部通过 / 2 有不符
"""
import re
import sys
import zipfile


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('用法: python check_mix.py <mixed.theme>\n')
        return 1
    path = argv[1]
    z = zipfile.ZipFile(path)
    info = z.read('themeInfo.xml').decode('utf-8', 'replace')
    decl = dict(re.findall(r'<package name="([^"]+)" version="([^"]*)"', info))

    checks = [
        ('icons 来自 B', z.read('icons') == b'PK\x03\x04B-icons-DIFFERENT'),
        ('settings 001 来自 B', z.read('com.android.settings') == b'PK\x03\x04B-settings-001'),
        ('settings 002 来自 B', z.read('com.android.settings_002') == b'PK\x03\x04B-settings-002'),
        ('wallpaper 保留 A', z.read('wallpaper') == b'PK\x03\x04A-wallpaper'),
        ('settings 版本沿用 B 的声明', decl.get('com.android.settings') == '001,002,003'),
        ('icons 版本为 001', decl.get('icons') == '001'),
        ('wallpaper 版本为 001', decl.get('wallpaper') == '001'),
        ('没有多余声明', set(decl) == {'icons', 'com.android.settings', 'wallpaper'}),
    ]

    bad = 0
    for label, ok in checks:
        print('  %s  %s' % ('[OK]' if ok else '[x] ', label))
        if not ok:
            bad += 1
    print('  声明: %s' % decl)
    return 0 if bad == 0 else 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
