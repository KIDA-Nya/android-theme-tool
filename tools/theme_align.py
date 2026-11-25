#!/usr/bin/env python3
"""theme_align.py —— 补全 ColorOS 主题包的模块声明。

背景
----
商城 UI 的应用路径（apply/n9b）是**扫描 zip 实际条目**来决定装哪些模块
（BaseUtil.isBelongToModuleIcons）；
而 ThemeApplyService 捷径只认 themeInfo.xml 里的 <packageInfo> 列表，
逐个 zipFile.getEntry(name) 解包。

结果就是：zip 里有 icons，但声明里没有 -> 图标不会被应用，
甚至会把系统里已应用的图标模块覆盖掉。

本脚本扫描真实条目，反推出完整的 <packageInfo>，让两条路径结果一致。
注意它改变的是「声明」，不是让系统按内容识别。

用法
----
    python theme_align.py <src.theme> <out.theme>

退出码: 0 成功 / 1 参数错误 / 3 输入不是 ColorOS 主题包
"""
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

# 顶层这些目录不是「模块」
SKIP_EXACT = {'themeInfo.xml', 'themeinfo.xml'}
SKIP_PREFIX = ('picture/', 'previews/', 'descriptions/', 'resources/')

# 形如 com.android.systemui_002 的多版本条目
VER_RE = re.compile(r'^(.*)_(\d{2,3})$')


def die(msg, code=1):
    sys.stderr.write(msg.rstrip() + '\n')
    return code


def load(src):
    """返回 (xml_text, 条目名列表)。"""
    with zipfile.ZipFile(src) as z:
        names = [i.filename for i in z.infolist() if not i.is_dir()]
        if 'themeInfo.xml' not in names:
            return None, names
        xml = z.read('themeInfo.xml').decode('utf-8')
    return xml, names


def collect_declared(root):
    """现有声明：{name: [versions]}"""
    declared = {}
    holder = root.find('packageInfo')
    if holder is None:
        return declared
    for node in holder.findall('package'):
        name = node.get('name')
        if not name:
            continue
        versions = [v.strip() for v in (node.get('version') or '001').split(',') if v.strip()]
        declared[name] = versions or ['001']
    return declared


def derive_from_entries(names):
    """从真实条目推导模块：{name: set(versions)}"""
    derived = {}
    for n in names:
        if n in SKIP_EXACT or n.startswith(SKIP_PREFIX):
            continue
        base, ver = n, '001'
        m = VER_RE.match(n)
        if m:
            base, ver = m.group(1), m.group(2)
        derived.setdefault(base, set()).add(ver)
    return derived


def build_package_info(merged):
    sort_ver = lambda vs: ','.join(sorted(vs))
    lines = ['  <packageInfo>']
    for name in sorted(merged):
        lines.append('    <package name="%s" version="%s" />' % (name, sort_ver(merged[name])))
    lines.append('  </packageInfo>')
    return '\n'.join(lines)


def rewrite_xml(xml, merged):
    """把 <packageInfo> 换成完整版本；若原本没有则插到根节点结尾前。"""
    block = build_package_info(merged)

    new_xml, n = re.subn(r'[ \t]*<packageInfo>.*?</packageInfo>', block, xml, flags=re.S)
    if n == 0:
        # 也兼容自闭合写法
        new_xml, n = re.subn(r'[ \t]*<packageInfo\s*/>', block, xml)
    if n == 0:
        # 完全没有 packageInfo：插到最后一个闭合标签之前
        idx = new_xml.rfind('</')
        new_xml = xml[:idx] + block + '\n' + xml[idx:]

    # 校验仍然是合法 XML
    ET.fromstring(new_xml)
    return new_xml


def copy_zip(src, dst, new_xml):
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w') as zout:
        for info in zin.infolist():
            data = new_xml.encode('utf-8') if info.filename == 'themeInfo.xml' else zin.read(info.filename)
            out = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            out.compress_type = info.compress_type
            out.external_attr = info.external_attr
            out.internal_attr = info.internal_attr
            out.create_system = info.create_system
            zout.writestr(out, data)


def main(argv):
    if len(argv) != 3:
        return die('用法: python theme_align.py <src.theme> <out.theme>')

    src, dst = argv[1], argv[2]
    if not os.path.isfile(src):
        return die('找不到输入文件: %s' % src)

    try:
        xml, names = load(src)
    except zipfile.BadZipFile:
        return die('不是有效的 zip: %s' % src, 3)

    if xml is None:
        return die('不是 ColorOS 主题包（缺少根级 themeInfo.xml）: %s' % src, 3)

    root = ET.fromstring(xml)
    declared = collect_declared(root)
    derived = derive_from_entries(names)

    merged = {k: set(v) for k, v in declared.items()}
    for name, versions in derived.items():
        merged.setdefault(name, set()).update(versions)

    added = sorted(set(merged) - set(declared))
    extended = {k: sorted(merged[k]) for k in declared if sorted(merged[k]) != sorted(set(declared[k]))}

    print('原声明 %d 项，条目推导 %d 项' % (len(declared), len(derived)))
    for name in added:
        print('  + %s  versions=%s' % (name, sorted(merged[name])))
    for name, vs in extended.items():
        print('  ~ %s: %s -> %s' % (name, sorted(set(declared[name])), vs))
    if not added and not extended:
        print('声明已完整，无需改动')

    try:
        new_xml = rewrite_xml(xml, merged)
    except ET.ParseError as exc:
        return die('重写后 XML 不合法: %s' % exc)

    copy_zip(src, dst, new_xml)

    print('')
    print('输出: %s  %s bytes' % (dst, format(os.path.getsize(dst), ',')))
    print('最终声明:')
    for name in sorted(merged):
        print('  %-34s %s' % (name, ','.join(sorted(merged[name]))))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
