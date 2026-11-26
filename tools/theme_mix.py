"""把多个 ColorOS 主题包的模块拼成一个"混搭"主题包。

原理：ColorOS 的 ThemeApplyService 只接受"整包"，商店的混搭功能其实是
客户端自己把各模块拼成一个包再走同一条路。本工具做同样的事。

用法：
    # 以 base.theme 为底，把 icons 换成 other.theme 里的 icons
    python theme_mix.py -o mixed.theme base.theme icons:other.theme

    # 同时替换多个模块
    python theme_mix.py -o mixed.theme base.theme \
        icons:a.theme com.android.systemui:b.theme wallpaper:c.theme

    # 只要某几个模块（其余丢掉）
    python theme_mix.py -o only-icons.theme base.theme --only icons

    # 顺手换 UUID（便于强制重新应用）
    python theme_mix.py -o mixed.theme base.theme icons:a.theme --new-uuid

参数：
    MODULE:PATH  用 PATH 这个主题包里的 MODULE 模块替换 base 的同名模块
                 MODULE 写基名即可（如 icons、com.android.settings）；
                 带版本后缀的条目（xxx_002）会一起被搬过来。

退出码：0 成功 / 1 参数或文件问题 / 2 主题结构问题
"""
import argparse
import io
import os
import re
import sys
import uuid
import zipfile


class MixError(Exception):
    pass


def read_theme(path):
    """读主题包，返回 (zip 对象, themeInfo.xml 文本, 模块 -> 条目名列表)。"""
    if not os.path.isfile(path):
        raise MixError('找不到文件：%s' % path)
    z = zipfile.ZipFile(path)
    try:
        info = z.read('themeInfo.xml').decode('utf-8', 'replace')
    except KeyError:
        z.close()
        raise MixError('%s 缺少根级 themeInfo.xml，不是 ColorOS 主题包' % os.path.basename(path))

    modules = {}
    for name in z.namelist():
        if name.endswith('/'):
            continue
        if name == 'themeInfo.xml':
            continue
        if name.startswith(('picture/', 'previews/', 'descriptions/', 'resources/')):
            continue
        base = re.sub(r'_\d{2,3}$', '', name)
        modules.setdefault(base, []).append(name)
    return z, info, modules


def declared_modules(info):
    """从 themeInfo.xml 的 packageInfo 里取声明过的模块名。"""
    return set(re.findall(r'<package\s+name="([^"]+)"', info))


def parse_versions(info):
    """取出 <package name=... version=...> 的映射。"""
    versions = {}
    for name, attrs in re.findall(r'<package\s+name="([^"]+)"([^>]*)/?>', info):
        vm = re.search(r'version="([^"]*)"', attrs)
        versions[name] = vm.group(1) if vm else '001'
    return versions


def replace_declarations(info, plan):
    """按最终包含的模块重写 packageInfo 段落；版本优先沿用来源主题的声明。"""
    base_versions = parse_versions(info)

    lines = []
    for name in sorted(plan):
        src_info = plan[name][2]
        ver = parse_versions(src_info).get(name) or base_versions.get(name) or '001'
        lines.append('        <package name="%s" version="%s" />' % (name, ver))
    block = '<packageInfo>\n%s\n    </packageInfo>' % '\n'.join(lines)

    if re.search(r'<packageInfo>.*?</packageInfo>', info, re.S):
        return re.sub(r'<packageInfo>.*?</packageInfo>', block, info, count=1, flags=re.S)
    # 没有 packageInfo 就插到根节点开头
    return re.sub(r'(<OplusSmartPhoneThemeInfo[^>]*>)', r'\1\n    ' + block, info, count=1)


def rotate_uuid(info, new_id):
    info = re.sub(r'<UUID>[^<]*</UUID>', '<UUID>%s</UUID>' % new_id, info, count=1)
    info = re.sub(r'<PackageName>[^<]*</PackageName>', '<PackageName>%s</PackageName>' % new_id, info, count=1)
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(
        description='把多个 ColorOS 主题包的模块拼成一个混搭包',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument('base', help='作为底的主题包')
    ap.add_argument('replacements', nargs='*', metavar='MODULE:PATH',
                    help='用 PATH 里的 MODULE 替换 base 的同名模块')
    ap.add_argument('-o', '--out', required=True, help='输出的主题包路径')
    ap.add_argument('--only', nargs='+', metavar='MODULE',
                    help='只保留这些模块（其余丢弃）')
    ap.add_argument('--new-uuid', action='store_true', help='生成新 UUID，便于强制重新应用')
    ap.add_argument('--dry-run', action='store_true', help='只打印计划，不写文件')
    args = ap.parse_args(argv)

    try:
        base_zip, base_info, base_mods = read_theme(args.base)
    except MixError as e:
        print('[x] %s' % e)
        return 1

    plan = {}          # 模块基名 -> (来源 zip, [条目名], 来源 themeInfo.xml)
    for name, entries in base_mods.items():
        plan[name] = (base_zip, entries, base_info)

    extra_zips = []
    for spec in args.replacements:
        if ':' not in spec:
            print('[x] 替换项格式应为 MODULE:PATH，收到：%s' % spec)
            return 1
        module, path = spec.split(':', 1)   # 只按第一个冒号切，兼容 Windows 盘符
        try:
            z, info, mods = read_theme(path)
        except MixError as e:
            print('[x] %s' % e)
            return 1
        extra_zips.append(z)
        if module not in mods:
            print('[x] %s 里没有模块 %s（可用：%s）'
                  % (os.path.basename(path), module, ', '.join(sorted(mods))))
            return 2
        plan[module] = (z, mods[module], info)

    if args.only:
        wanted = set(args.only)
        missing = wanted - set(plan)
        if missing:
            print('[x] base 里没有这些模块：%s' % ', '.join(sorted(missing)))
            return 2
        plan = {k: v for k, v in plan.items() if k in wanted}

    # 声明：只保留最终仍在包里的模块，版本沿用 base 的写法
    info = replace_declarations(base_info, plan)
    if args.new_uuid:
        new_id = uuid.uuid4().hex.upper()
        info = rotate_uuid(info, new_id)

    total = sum(len(v[1]) for v in plan.values())
    print('底包 : %s' % os.path.basename(args.base))
    print('模块 : %d 个（条目 %d 个）' % (len(plan), total))
    for name in sorted(plan):
        z, entries, _src = plan[name]
        src = os.path.basename(z.filename or '<base>')
        print('   %-28s <- %-28s %d 条目' % (name, os.path.basename(src), len(entries)))

    if args.dry_run:
        print('（dry-run，未写文件）')
        return 0

    if os.path.exists(args.out):
        print('[x] 输出文件已存在，请换路径或先删除：%s' % args.out)
        return 1

    written = 0
    with zipfile.ZipFile(args.out, 'w', zipfile.ZIP_DEFLATED) as out:
        out.writestr('themeInfo.xml', info)

        # picture/ 等预览资源沿用 base
        for name in base_zip.namelist():
            if name.endswith('/'):
                continue
            if name == 'themeInfo.xml':
                continue
            if name.startswith(('picture/', 'previews/', 'descriptions/', 'resources/')):
                out.writestr(name, base_zip.read(name))
                written += 1

        for name in sorted(plan):
            z, entries, _src = plan[name]
            for entry in entries:
                out.writestr(entry, z.read(entry))
                written += 1

    for z in extra_zips:
        z.close()
    base_zip.close()

    print('输出 : %s（%s）' % (args.out, fmt_size(os.path.getsize(args.out))))
    print('完成：%d 个条目' % written)
    return 0


def fmt_size(n):
    for unit in ('B', 'KB', 'MB'):
        if n < 1024 or unit == 'MB':
            return '%.1f %s' % (n, unit) if unit != 'B' else '%d B' % n
        n /= 1024.0


if __name__ == '__main__':
    sys.exit(main())
