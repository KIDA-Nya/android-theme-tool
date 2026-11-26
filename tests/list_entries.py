"""列出主题包里的条目（除 themeInfo.xml），逗号分隔。

用法: python list_entries.py <theme>
"""
import sys
import zipfile


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('用法: python list_entries.py <theme>\n')
        return 1
    with zipfile.ZipFile(argv[1]) as z:
        names = [n for n in z.namelist() if n != 'themeInfo.xml']
    print(','.join(names))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
