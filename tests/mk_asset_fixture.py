"""生成用于 extract_assets.py 的测试主题包。

覆盖两种结构：
  nested.theme  ColorOS 风格：模块本身是内嵌 zip（壁纸/图标在里层）
  flat.hwt      华为风格：目录直接平铺（wallpaper/ icons/ fonts/）
"""
import io
import os
import sys
import zipfile

THEME_INFO = """<?xml version='1.0' encoding='utf-8'?>
<OplusSmartPhoneThemeInfo>
  <Summary>extract fixture</Summary>
  <EditorVersion>16000</EditorVersion>
  <UUID>CCCC3333CCCC3333CCCC3333CCCC3333</UUID>
  <packageInfo>
    <package name="wallpaper" version="001" />
    <package name="icons" version="001" />
  </packageInfo>
</OplusSmartPhoneThemeInfo>
"""

HWT_DESC = """<?xml version="1.0" encoding="UTF-8"?>
<HwTheme><title>flat fixture</title><version>11.0.0</version></HwTheme>
"""

PNG = b'\x89PNG\r\n\x1a\n' + b'\x00' * 32
JPG = b'\xff\xd8\xff\xe0' + b'\x00' * 32
TTF = b'\x00\x01\x00\x00' + b'\x00' * 32
OGG = b'OggS' + b'\x00' * 32


def nested_zip(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, d in files.items():
            z.writestr(n, d)
    return buf.getvalue()


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('用法: python mk_asset_fixture.py <out_dir>\n')
        return 1
    out = argv[1]
    os.makedirs(out, exist_ok=True)

    # --- ColorOS 风格：模块是内嵌 zip ---
    wp = nested_zip({'res/drawable-xxhdpi/oppo_default_wallpaper.jpg': JPG})
    ic = nested_zip({'res/drawable-xxhdpi/com.example.app.png': PNG,
                     'allApps.xml': b'<iconinfo/>'})
    p = os.path.join(out, 'nested.theme')
    with zipfile.ZipFile(p, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('themeInfo.xml', THEME_INFO)
        z.writestr('wallpaper', wp)
        z.writestr('icons', ic)
        z.writestr('fonts/MyFont.ttf', TTF)
        z.writestr('ringtone/alarm.ogg', OGG)
    print('nested.theme  %d bytes' % os.path.getsize(p))

    # --- 华为风格：目录平铺 ---
    p2 = os.path.join(out, 'flat.hwt')
    with zipfile.ZipFile(p2, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('description.xml', HWT_DESC)
        z.writestr('wallpaper/home_wallpaper_0.jpg', JPG)
        z.writestr('icons/com.example.app.png', PNG)
        z.writestr('fonts/Other.ttf', TTF)
    print('flat.hwt      %d bytes' % os.path.getsize(p2))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
