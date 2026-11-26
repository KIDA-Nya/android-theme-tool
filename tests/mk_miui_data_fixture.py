"""生成小米商店 .data 库与 .mtz 的测试夹具（用于 miui_backup_inject.py）。

布局仿照真实结构：
  <out>/.data/meta/theme/<themeId>.mrm   主题元数据（titles.fallback = "Theme backup"）
  <out>/.data/meta/icons/<id>.mrm        组件元数据（hash / size）
  <out>/.data/content/icons/<id>.mrc     组件本体（zip）
  <out>/sample.mtz                       待注入的主题包
"""
import hashlib
import io
import json
import os
import sys
import zipfile

THEME_ID = 'THEMEBACKUP0000000000000000000001'
OLD_ICONS_ID = 'OLDICONS00000000000000000000000001'


def zip_bytes(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, d in files.items():
            z.writestr(n, d)
    return buf.getvalue()


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = 'wb' if isinstance(data, bytes) else 'w'
    with open(path, mode, **({} if isinstance(data, bytes) else {'encoding': 'utf-8'})) as f:
        f.write(data)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('用法: python mk_miui_data_fixture.py <out_dir>\n')
        return 1
    out = argv[1]
    data = os.path.join(out, '.data')

    # 老图标组件
    old_mrc = zip_bytes({'com.old.app.png': b'OLD-ICON'})
    write(os.path.join(data, 'content', 'icons', OLD_ICONS_ID + '.mrc'), old_mrc)
    write(os.path.join(data, 'meta', 'icons', OLD_ICONS_ID + '.mrm'), json.dumps({
        'hash': hashlib.sha1(old_mrc).hexdigest(),
        'size': len(old_mrc),
        'titles': {'fallback': 'Theme backup icons'},
    }, ensure_ascii=False, indent=2))

    # 主题元数据：一个 Theme backup，只有一个 icons 组件
    write(os.path.join(data, 'meta', 'theme', THEME_ID + '.mrm'), json.dumps({
        'localId': THEME_ID,
        'titles': {'fallback': 'Theme backup'},
        'productId': None,
        'onlineId': None,
        'components': [
            {'resourceCode': 'icons', 'localId': OLD_ICONS_ID},
        ],
    }, ensure_ascii=False, indent=2))

    # 待注入的 .mtz
    mtz = os.path.join(out, 'sample.mtz')
    with zipfile.ZipFile(mtz, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('description.xml', '<MIUI_Theme><title>t</title></MIUI_Theme>')
        z.writestr('icons/com.example.app.png', b'NEW-ICON-BYTES')
        z.writestr('wallpaper/w.jpg', b'\xff\xd8')
    print('夹具已生成：%s' % out)
    print('  data  : %s' % data)
    print('  mtz   : %s' % mtz)
    print('  theme : %s' % THEME_ID)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
