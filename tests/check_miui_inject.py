"""校验 miui_backup_inject.py 的注入结果（与 mk_miui_data_fixture.py 配套）。

用法: python check_miui_inject.py <fixture_dir>
退出码: 0 通过 / 2 不符
"""
import hashlib
import io
import json
import os
import sys
import zipfile

THEME_ID = 'THEMEBACKUP0000000000000000000001'


def load(p):
    with io.open(p, encoding='utf-8') as f:
        return json.load(f)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('用法: python check_miui_inject.py <fixture_dir>\n')
        return 1
    root = argv[1]
    data = os.path.join(root, '.data')

    theme = load(os.path.join(data, 'meta', 'theme', THEME_ID + '.mrm'))
    comps = theme.get('components') or []
    icons = [c for c in comps if c.get('resourceCode') == 'icons']
    if not icons:
        print('  [x] 主题元数据里没有 icons 组件')
        return 2
    new_id = icons[0].get('localId')

    checks = [('localId 已改（不再是老的）', new_id != 'OLDICONS00000000000000000000000001'),
              ('localId 是 32 位十六进制', isinstance(new_id, str) and len(new_id) == 32)]

    mrc = os.path.join(data, 'content', 'icons', (new_id or '') + '.mrc')
    mrm = os.path.join(data, 'meta', 'icons', (new_id or '') + '.mrm')
    checks.append(('.mrc 已生成', os.path.isfile(mrc)))
    checks.append(('.mrm 已生成', os.path.isfile(mrm)))

    if os.path.isfile(mrc) and os.path.isfile(mrm):
        payload = open(mrc, 'rb').read()
        meta = load(mrm)
        checks.append(('hash 与 .mrc 一致', meta.get('hash') == hashlib.sha1(payload).hexdigest()))
        checks.append(('size 与 .mrc 一致', meta.get('size') == len(payload)))
        with zipfile.ZipFile(io.BytesIO(payload)) as z:
            names = z.namelist()
        checks.append(('内容来自 .mtz 的 icons 模块', 'com.example.app.png' in names))
        checks.append(('没有把 wallpaper 混进来', not any('wallpaper' in n for n in names)))
    else:
        checks.extend([('hash 与 .mrc 一致', False) for _ in range(4)])

    bad = 0
    for label, ok in checks:
        print('  %s  %s' % ('[OK]' if ok else '[x] ', label))
        if not ok:
            bad += 1
    return 0 if bad == 0 else 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
