#!/usr/bin/env python3
"""newuuid.py —— 给主题包换一个新的 UUID。

为什么要换
----------
系统以 `applied_default_theme_package_name`（= 主题的 UUID）判断「是否已是当前主题」。
UUID 相同就不再重做，于是重复应用同一个主题会表现为「卡住 / 无反应」。
换一个 UUID 可以强制系统重新走一遍完整应用流程。

用法
----
    python newuuid.py <src.theme> <out.theme>

退出码: 0 成功 / 1 参数或文件问题 / 3 不是 ColorOS 主题包
"""
import os
import re
import sys
import uuid
import zipfile

TAG_RE = {'UUID': r'<UUID>[^<]*</UUID>', 'PackageName': r'<PackageName>[^<]*</PackageName>'}


def die(msg, code=1):
    sys.stderr.write(msg.rstrip() + '\n')
    return code


def main(argv):
    if len(argv) != 3:
        return die('用法: python newuuid.py <src.theme> <out.theme>')

    src, dst = argv[1], argv[2]
    if not os.path.isfile(src):
        return die('找不到输入文件: %s' % src)
    if os.path.abspath(src) == os.path.abspath(dst):
        return die('输出不能覆盖输入，请指定另一个文件名。')

    try:
        with zipfile.ZipFile(src) as z:
            names = z.namelist()
            if 'themeInfo.xml' not in names:
                return die('不是 ColorOS 主题包（缺少根级 themeInfo.xml）: %s' % src, 3)
            xml = z.read('themeInfo.xml').decode('utf-8')
    except zipfile.BadZipFile:
        return die('不是有效的 zip: %s' % src, 3)

    new_id = uuid.uuid4().hex.upper()

    replaced = []
    for tag, pattern in TAG_RE.items():
        new_xml, n = re.subn(pattern, '<%s>%s</%s>' % (tag, new_id, tag), xml)
        if n:
            replaced.append(tag)
            xml = new_xml

    if not replaced:
        return die(
            '主题里既没有 <UUID> 也没有 <PackageName>，无法改 ID。\n'
            '这个包可能不是标准 ColorOS 主题。'
        )

    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w') as zout:
        for info in zin.infolist():
            data = xml.encode('utf-8') if info.filename == 'themeInfo.xml' else zin.read(info.filename)
            out = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            out.compress_type = info.compress_type
            out.external_attr = info.external_attr
            out.internal_attr = info.internal_attr
            out.create_system = info.create_system
            zout.writestr(out, data)

    print('新 ID : %s' % new_id)
    print('改写  : %s' % ', '.join(replaced))
    print('输出  : %s  %s bytes' % (dst, format(os.path.getsize(dst), ',')))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
