"""比较两张图片是否相同（缩放后算平均像素差），用于验证壁纸是否真的被写入。

用法: python pixel_diff.py <图片A> <图片B> [阈值]
输出「平均像素差」；差值 <= 阈值(默认 1.0) 视为相同，退出码 0，否则 2。
非图片文件（如二进制壁纸文件）按图片格式尝试打开。
"""
import statistics
import sys


def main(argv):
    if len(argv) < 3:
        sys.stderr.write('用法: python pixel_diff.py <A> <B> [阈值]\n')
        return 1
    try:
        from PIL import Image, ImageChops
    except ImportError:
        sys.stderr.write('需要 Pillow：python -m pip install pillow\n')
        return 3

    a_path, b_path = argv[1], argv[2]
    thresh = float(argv[3]) if len(argv) > 3 else 1.0

    def prep(p):
        return Image.open(p).convert('RGB').resize((64, 64), Image.LANCZOS)

    try:
        a, b = prep(a_path), prep(b_path)
    except Exception as exc:
        sys.stderr.write('打开图片失败：%s\n' % exc)
        return 3

    diff = list(ImageChops.difference(a, b).getdata())
    mean = statistics.mean(sum(c) / 3 for c in diff)
    print('A: %s %s' % (a_path, Image.open(a_path).size))
    print('B: %s %s' % (b_path, Image.open(b_path).size))
    print('平均像素差: %.2f（阈值 %.2f）' % (mean, thresh))
    if mean <= thresh:
        print('结论: 相同')
        return 0
    print('结论: 不同')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
