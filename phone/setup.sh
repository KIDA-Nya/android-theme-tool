#!/data/data/com.termux/files/usr/bin/sh
# 主题工具 · 手机端一次性安装脚本（在 Termux 里运行一次）
#
#   sh /sdcard/Download/setup.sh
#
# 做三件事：
#   1. 把 Shizuku 的 rish 装到 ~/bin
#   2. 生成 theme 命令（自动在 rish / su / 当前身份之间选）
#   3. 把 ~/bin 加进 PATH
#
# 之后只需输入：  theme

set -u

BIN="$HOME/bin"
SHIZUKU_DIR="/sdcard/Android/data/moe.shizuku.privileged.api"
SCRIPT="/sdcard/Download/theme.sh"

echo ""
echo "=== 主题工具 · 安装 ==="

mkdir -p "$BIN" || { echo "  [x] 无法创建 $BIN"; exit 1; }

# ---------------------------------------------------------------- 1) rish

if [ -f "$SHIZUKU_DIR/rish" ]; then
    cp -f "$SHIZUKU_DIR/rish" "$BIN/rish" 2>/dev/null
    # rish 依赖同目录的 dex
    for f in "$SHIZUKU_DIR"/rish_*.dex; do
        [ -f "$f" ] && cp -f "$f" "$BIN/" 2>/dev/null
    done
    chmod 700 "$BIN/rish" 2>/dev/null
    if [ -x "$BIN/rish" ]; then
        echo "  [OK] rish 已安装到 $BIN"
    else
        echo "  [!]  rish 复制后不可执行，请检查权限"
    fi
else
    echo "  [!]  没找到 rish"
    echo "      请先在 Shizuku 里打开「在终端应用中使用 Shizuku」："
    echo "      Shizuku → 右上角菜单 → 在终端应用中使用 Shizuku"
fi

# ---------------------------------------------------------------- 2) theme 命令

cat > "$BIN/theme" <<'WRAP'
#!/data/data/com.termux/files/usr/bin/sh
# 自动选择特权身份：root > rish > su > 当前身份
SCRIPT=/sdcard/Download/theme.sh
[ -f "$SCRIPT" ] || { echo "缺少 $SCRIPT，请先把 theme.sh 放到 /sdcard/Download/"; exit 1; }

# 给单个参数加双引号转义，避免路径含空格/特殊字符时被拆开
quote_arg() {
    printf '%s' "$1" | sed -e 's/[\\"$`]/\\&/g'
}

build_cmd() {
    out="sh $SCRIPT"
    for a in "$@"; do
        out="$out \"$(quote_arg "$a")\""
    done
    printf '%s' "$out"
}

if [ "$(id -u)" = "0" ]; then
    exec sh "$SCRIPT" "$@"
fi

if command -v rish >/dev/null 2>&1 && rish -c true >/dev/null 2>&1; then
    exec rish -c "$(build_cmd "$@")"
fi

if command -v su >/dev/null 2>&1 && su -c true >/dev/null 2>&1; then
    exec su -c "$(build_cmd "$@")"
fi

# 没有特权：直接跑（投递服务会被拒绝，但 --status 之类仍可用）
exec sh "$SCRIPT" "$@"
WRAP
chmod 700 "$BIN/theme" || true
echo "  [OK] theme 命令已安装"

# ---------------------------------------------------------------- 3) PATH

PATH_LINE='export PATH=$HOME/bin:$PATH'
added=0
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    # 只给已经存在、或 bash/zsh 的主配置文件写入
    case "$rc" in
        */.zshrc) [ -f "$rc" ] || [ -n "${ZSH_VERSION:-}" ] || continue ;;
        */.profile) [ -f "$rc" ] || continue ;;
    esac
    if ! grep -q 'HOME/bin' "$rc" 2>/dev/null; then
        printf '%s\n' "$PATH_LINE" >> "$rc"
        echo "  [OK] 已写入 $rc"
        added=1
    fi
done
[ "$added" = "0" ] && echo "  [OK] PATH 已配置过"

# ---------------------------------------------------------------- 4) 自检

echo ""
echo "=== 自检 ==="

if [ -x "$BIN/rish" ]; then
    if "$BIN/rish" -c id 2>/dev/null | grep -q 'uid=2000'; then
        echo "  [OK] rish 可用（shell 身份）"
    else
        echo "  [!]  rish 已装但执行失败：请确认 Shizuku 服务正在运行"
    fi
else
    echo "  [!]  未装 rish：将退回 su 或当前身份"
fi

if [ -f "$SCRIPT" ]; then
    echo "  [OK] 脚本在 $SCRIPT"
else
    echo "  [!]  缺少 $SCRIPT，请把 theme.sh 放到 /sdcard/Download/"
fi

if command -v zip >/dev/null 2>&1; then
    echo "  [OK] 已安装 zip（可以自动对齐模块声明）"
else
    echo "  [!]  未安装 zip：图标模块可能不生效，可执行 pkg install zip"
fi

if pm list packages 2>/dev/null | grep -qx 'package:com.keke.lockwall'; then
    echo "  [OK] lockwall 已安装（可设锁屏壁纸）"
else
    echo "  [!]  未安装 lockwall.apk（锁屏壁纸那一步会用不了）"
fi

echo ""
echo "完成。新开一个 Termux 窗口，直接输入："
echo ""
echo "    theme"
echo ""
echo "即可看到主题列表并选择应用。"
echo ""
