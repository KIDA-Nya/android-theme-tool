"""把 .mtz 里的模块注入到小米商店的 "Theme backup" 里（免 root，Shizuku/shell 可写）。

原理（来自 HyperOS 商店的实际布局，见 docs/MIUI-THEME-BACKUP.md）：
    /sdcard/Android/data/com.android.thememanager/files/MIUI/theme/.data/
        content/<code>/<id>.mrc      组件本体（一个 zip）
        meta/<code>/<id>.mrm         组件元数据 JSON（hash = SHA-1(.mrc)，size = 长度）
        meta/theme/<themeId>.mrm     主题元数据，列出各组件：resourceCode + localId

    "Theme backup" 是商店自己「定制主题」时生成的主题，**没有 rights 记录、应用时不需要联网授权**；
    手动塞进去的主题则会被 DRM 拦。所以不新建主题，而是把已有 backup 的组件指向我们的文件。

    这个目录 shell(uid 2000) 可读写，而 /data/system/theme 不行——应用时由商店自己拷过去。

用法：
    # 1) 列出设备上拉下来的库里有哪些 Theme backup
    python miui_backup_inject.py --data <拉下来的 .data 目录> --list

    # 2) 把某主题包的 icons 模块注入指定 backup
    python miui_backup_inject.py --data <.data 目录> --theme <themeId> \
        --mtz <主题.mtz> --component icons

    # 3) 支持 --dry-run 先看计划
"""
import argparse
import hashlib
import io
import json
import os
import sys
import uuid
import zipfile

BACKUP_TITLE = 'Theme backup'


# ---------------------------------------------------------------- 基础操作

def load_json(path):
    with io.open(path, 'r', encoding='utf-8', errors='replace') as f:
        return json.load(f)


def dump_json(path, obj):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def themes(data_dir):
    """列出 meta/theme 下的全部主题元数据。"""
    d = os.path.join(data_dir, 'meta', 'theme')
    if not os.path.isdir(d):
        return []
    out = []
    for name in sorted(os.listdir(d)):
        if not name.endswith('.mrm'):
            continue
        p = os.path.join(d, name)
        try:
            j = load_json(p)
        except Exception:
            continue
        out.append((name[:-4], p, j))
    return out


def title_of(j):
    t = j.get('titles') or {}
    return t.get('fallback') or ''


def components_of(j):
    """主题元数据里的组件列表；不同版本可能是 list 或 dict。"""
    for key in ('components', 'componentList', 'parts'):
        v = j.get(key)
        if isinstance(v, list):
            return v
        if isinstance(v, dict):
            return list(v.values())
    return []


def find_component(j, code):
    for c in components_of(j):
        if isinstance(c, dict) and c.get('resourceCode') == code:
            return c
    return None


# ---------------------------------------------------------------- 注入

def mtz_module(mtz_path, code):
    """从 .mtz 里取出某个模块（顶层目录 <code>/ 下的所有条目），打成一个 zip。"""
    with zipfile.ZipFile(mtz_path) as z:
        names = [n for n in z.namelist()
                 if n == code + '/' or n.startswith(code + '/')]
        if not names:
            return None, []
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as out:
            for n in names:
                if n.endswith('/'):
                    continue
                out.writestr(n[len(code) + 1:], z.read(n))
        return buf.getvalue(), names


def inject(args):
    data_dir = args.data
    if not os.path.isdir(data_dir):
        print('[x] 不是有效的 .data 目录：%s' % data_dir)
        return 1

    all_themes = themes(data_dir)
    if not all_themes:
        print('[x] 没找到任何主题元数据（meta/theme/*.mrm）。')
        print('    提示：需要先在手机上「定制主题 → 改一项 → 应用」生成 Theme backup。')
        return 2

    target = [t for t in all_themes if t[0] == args.theme]
    if not target:
        print('[x] 没有 id 为 %s 的主题。可用：' % args.theme)
        for tid, _p, j in all_themes:
            print('    %-40s %s' % (tid, title_of(j) or '(无标题)'))
        return 2
    theme_id, theme_path, theme_json = target[0]

    comp = find_component(theme_json, args.component)
    if not comp:
        print('[x] 这个主题里没有 resourceCode=%s 的组件。现有组件：'
              % args.component)
        for c in components_of(theme_json):
            if isinstance(c, dict):
                print('    %-14s localId=%s' % (c.get('resourceCode'), c.get('localId')))
        return 2

    payload, names = mtz_module(args.mtz, args.component)
    if payload is None:
        print('[x] %s 里没有 %s/ 模块' % (os.path.basename(args.mtz), args.component))
        return 2

    sha1 = hashlib.sha1(payload).hexdigest()
    size = len(payload)
    new_id = uuid.uuid4().hex
    content_path = os.path.join(data_dir, 'content', args.component, new_id + '.mrc')
    meta_path = os.path.join(data_dir, 'meta', args.component, new_id + '.mrm')

    print('主题      : %s（%s）' % (theme_id, title_of(theme_json)))
    print('组件      : %s → 新 localId %s' % (args.component, new_id))
    print('来源      : %s（%d 个条目）' % (os.path.basename(args.mtz), len([n for n in names if not n.endswith('/')])))
    print('新 .mrc   : %s（%d 字节，sha1 %s）' % (content_path, size, sha1))

    if args.dry_run:
        print('（dry-run，未写文件）')
        return 0

    os.makedirs(os.path.dirname(content_path), exist_ok=True)
    with open(content_path, 'wb') as f:
        f.write(payload)

    # 组件元数据：尽量沿用原组件的字段，只改必要的
    old_meta = None
    old_id = comp.get('localId')
    if old_id:
        p = os.path.join(data_dir, 'meta', args.component, old_id + '.mrm')
        if os.path.isfile(p):
            try:
                old_meta = load_json(p)
            except Exception:
                old_meta = None
    meta = dict(old_meta) if old_meta else {}
    meta['hash'] = sha1
    meta['size'] = size
    meta.setdefault('titles', {})['fallback'] = args.title
    dump_json(meta_path, meta)
    print('新 .mrm   : %s' % meta_path)

    # 主题元数据：把该组件的 localId 指向新文件
    comp['localId'] = new_id
    dump_json(theme_path, theme_json)
    print('主题元数据: %s（localId 已改为 %s）' % (theme_path, new_id))

    if args.report:
        rel = [
            os.path.relpath(content_path, data_dir).replace('\\', '/'),
            os.path.relpath(meta_path, data_dir).replace('\\', '/'),
            os.path.relpath(theme_path, data_dir).replace('\\', '/'),
        ]
        dump_json(args.report, {'changed': rel, 'themeId': theme_id, 'component': args.component,
                                'newId': new_id, 'sha1': sha1, 'size': size})

    print('\n完成。回到手机：')
    print('  1) 主题应用里选中「%s」→ 应用' % (title_of(theme_json) or BACKUP_TITLE))
    print('  2) 应用后 /data/system/theme/%s 会由商店自己写入' % args.component)
    return 0


# ---------------------------------------------------------------- 入口

def main(argv=None):
    ap = argparse.ArgumentParser(
        description='把 .mtz 模块注入小米商店的 Theme backup（免 root）',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument('--data', required=True,
                    help='从设备拉下来的 …/MIUI/theme/.data 目录')
    ap.add_argument('--list', action='store_true', help='列出库里的主题与组件')
    ap.add_argument('--theme', help='要注入的 Theme backup 的 localId')
    ap.add_argument('--mtz', help='提供模块的 .mtz 主题包')
    ap.add_argument('--component', default='icons', help='模块代码，默认 icons')
    ap.add_argument('--title', default='Injected icons', help='新组件在商店里的显示名')
    ap.add_argument('--dry-run', action='store_true', help='只打印计划')
    ap.add_argument('--report', help='把改动文件清单写入这个 JSON（供上层只回推改动）')
    args = ap.parse_args(argv)

    if args.list:
        rows = themes(args.data)
        if not rows:
            print('[x] 没找到主题元数据（meta/theme/*.mrm）')
            return 2
        print('主题数：%d' % len(rows))
        for tid, _p, j in rows:
            mark = '  <= Theme backup' if title_of(j) == BACKUP_TITLE else ''
            print('  %s  %s%s' % (tid, title_of(j) or '(无标题)', mark))
            for c in components_of(j):
                if isinstance(c, dict):
                    print('      %-12s %s' % (c.get('resourceCode'), c.get('localId')))
        return 0

    if not args.theme or not args.mtz:
        ap.print_help()
        return 1

    return inject(args)


if __name__ == '__main__':
    sys.exit(main())
