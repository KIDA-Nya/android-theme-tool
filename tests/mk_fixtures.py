"""生成 mtz/hwt 合成夹具，用于测试只读校验器。

用法: python mk_fixtures.py <out_dir>
"""
import os
import sys
import zipfile

MIUI_DESC = """<?xml version="1.0" encoding="UTF-8"?>
<MIUI_Theme>
  <title>Test MIUI</title>
  <author>tester</author>
  <version>1.0</version>
</MIUI_Theme>
"""

HWT_DESC = """<?xml version="1.0" encoding="UTF-8"?>
<HwTheme>
  <title>Test HWT</title>
  <title-cn>测试主题</title-cn>
  <author>tester</author>
  <screen>FHD</screen>
  <version>11.0.0</version>
</HwTheme>
"""


def mk(out_dir, name, files):
    path = os.path.join(out_dir, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, data in files.items():
            z.writestr(n, data)
    print("%-16s %6d bytes" % (name, os.path.getsize(path)))


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("用法: python mk_fixtures.py <out_dir>\n")
        return 1
    out = argv[1]
    os.makedirs(out, exist_ok=True)

    png = b"\x89PNG\r\n\x1a\n"
    jpg = b"\xff\xd8\xff\xe0"

    # 正常 MIUI 包
    mk(out, "good.mtz", {
        "description.xml": MIUI_DESC,
        "icons/a.png": png,
        "lockscreen/b.png": png,
        "wallpaper/c.jpg": jpg,
    })

    # 缺描述文件
    mk(out, "nodesc.mtz", {"icons/a.png": png})

    # 正常华为包
    mk(out, "good.hwt", {
        "description.xml": HWT_DESC,
        "wallpaper/a.jpg": jpg,
        "icons/a.png": png,
    })

    # 根节点不对
    mk(out, "badroot.hwt", {
        "description.xml": '<?xml version="1.0" encoding="UTF-8"?><NotHwTheme><version>1</version></NotHwTheme>',
        "wallpaper/a.jpg": jpg,
    })

    # 不是主题包
    mk(out, "unknown.bin", {"readme.txt": "nothing here"})

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
