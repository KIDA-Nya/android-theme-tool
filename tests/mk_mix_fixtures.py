"""生成用于 theme_mix.py 测试的两个主题包（A 为底，B 提供替换模块）。

用法: python mk_mix_fixtures.py <out_dir>
"""
import io
import os
import sys
import zipfile

INFO = """<?xml version='1.0' encoding='utf-8'?>
<OplusSmartPhoneThemeInfo>
  <Author>tester</Author>
  <Summary>%s</Summary>
  <EditorVersion>16000</EditorVersion>
  <UUID>%s</UUID>
  <PackageName>%s</PackageName>
  <packageInfo>
%s
  </packageInfo>
</OplusSmartPhoneThemeInfo>
"""


def info(summary, uid, mods):
    lines = '\n'.join('    <package name="%s" version="%s" />' % (m, v) for m, v in mods)
    return INFO % (summary, uid, uid, lines)


def write(path, summary, uid, mods, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('themeInfo.xml', info(summary, uid, mods))
        for name, data in entries.items():
            z.writestr(name, data)
    print('%-14s %6d bytes' % (os.path.basename(path), os.path.getsize(path)))


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('用法: python mk_mix_fixtures.py <out_dir>\n')
        return 1
    out = argv[1]
    os.makedirs(out, exist_ok=True)

    # A：底包，含 icons / wallpaper / com.android.settings（带 002 变体）
    write(os.path.join(out, 'a.theme'), 'A 底包', 'AAAA1111AAAA1111AAAA1111AAAA1111',
          [('icons', '001'), ('wallpaper', '001'), ('com.android.settings', '001,002')],
          {
              'icons': b'PK\x03\x04A-icons',
              'wallpaper': b'PK\x03\x04A-wallpaper',
              'com.android.settings': b'PK\x03\x04A-settings-001',
              'com.android.settings_002': b'PK\x03\x04A-settings-002',
          })

    # B：替换源，icons 与 settings 内容不同，且设置模块声明了别的版本串
    write(os.path.join(out, 'b.theme'), 'B 替换源', 'BBBB2222BBBB2222BBBB2222BBBB2222',
          [('icons', '001'), ('com.android.settings', '001,002,003'), ('wallpaper', '001')],
          {
              'icons': b'PK\x03\x04B-icons-DIFFERENT',
              'wallpaper': b'PK\x03\x04B-wallpaper-DIFFERENT',
              'com.android.settings': b'PK\x03\x04B-settings-001',
              'com.android.settings_002': b'PK\x03\x04B-settings-002',
          })
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
