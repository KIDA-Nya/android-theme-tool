#!/data/data/com.termux/files/usr/bin/sh
# ============================================================
#  Termux:Widget 入口 —— 桌面点一下，应用 Download 里最新的主题
#
#  安装：
#    1. 装 Termux:Widget（F-Droid / Play）
#    2. mkdir -p ~/.shortcuts
#    3. cp /sdcard/Download/widget.sh ~/.shortcuts/主题
#    4. chmod +x ~/.shortcuts/主题
#    5. 长按桌面 → 小部件 → Termux:Widget → 选「主题」
#
#  想改成"只应用不换锁屏"，把下面的 --latest 改成 --latest --no-lock
#  想指定固定文件，把 --latest 换成具体路径
# ============================================================

THEME_CMD="$HOME/bin/theme"

if [ -x "$THEME_CMD" ]; then
    exec "$THEME_CMD" --latest
fi

# 没跑过 setup.sh：退回到直接找 rish / su
SCRIPT=/sdcard/Download/theme.sh
[ -f "$SCRIPT" ] || { echo "缺少 $SCRIPT"; exit 1; }

if command -v rish >/dev/null 2>&1 && rish -c true >/dev/null 2>&1; then
    exec rish -c "sh $SCRIPT --latest"
fi

if command -v su >/dev/null 2>&1 && su -c true >/dev/null 2>&1; then
    exec su -c "sh $SCRIPT --latest"
fi

exec sh "$SCRIPT" --latest
