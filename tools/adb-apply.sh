#!/usr/bin/env sh
# 用纯 adb 把本地 .theme 投递给系统主题商店并应用。
#
# 不依赖 PowerShell、不依赖 Python、不需要 root。
# 等价于在主题商店里点「应用」：把文件推到设备，再向 ThemeApplyService 投递 THEME_PATH。
#
# 用法：
#   ./adb-apply.sh <theme 路径>
#   ./adb-apply.sh --status
#   ADB_SERIAL=xxxx ./adb-apply.sh theme.theme     # 多设备时指定
#   ADB=/path/to/adb ./adb-apply.sh theme.theme    # 指定 adb 可执行文件
#
# 注意：
#   · 只做「投递 + 等待」，不做模块声明对齐。若主题里有 icons 但没在
#     themeInfo.xml 里声明，图标不会生效——这种情况请先用 tools/theme_align.py。
#   · 系统以 UUID 判断「是否已是当前主题」，重复投递同一主题会空转；
#     需要强制重来时先用 tools/newuuid.py 换 UUID。

set -u

# Git Bash / MSYS2 / Cygwin 会把参数里的 /sdcard/... 当成本地绝对路径改写，
# 导致 adb 收到 C:/Program Files/Git/sdcard/... 。这里关掉路径转换。
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        MSYS_NO_PATHCONV=1
        MSYS2_ARG_CONV_EXCL='*'
        export MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL
        ;;
esac
# 主题商店包名/服务组件在不同 ROM 上不同，下面会探测后填充
PKG=""
SVC=""
REMOTE=/sdcard/Download/theme_apply.theme
TIMEOUT=${TIMEOUT:-180}

ADB_BIN=${ADB:-adb}
ADB_SERIAL_ARG=
[ -n "${ADB_SERIAL:-}" ] && ADB_SERIAL_ARG="-s $ADB_SERIAL"

say()  { echo "  $*"; }
ok()   { echo "  [OK] $*"; }
warn() { echo "  [!]  $*"; }
die()  { echo "  [x]  $*"; exit 1; }

run() { $ADB_BIN $ADB_SERIAL_ARG "$@"; }

# ---------------------------------------------------------------- 探测主题商店

detect_store() {
    for p in com.heytap.themestore com.oplus.themestore com.nearme.themestore com.oppo.themestore; do
        $ADB shell "pm list packages $p" 2>/dev/null | tr -d '\r' | grep -qx "package:$p" || continue
        comp=$($ADB shell "dumpsys package $p" 2>/dev/null | tr -d '\r' \
               | grep -oE "$p/[^ ]*ThemeApplyService" | head -1)
        if [ -n "$comp" ]; then
            PKG=$p
            SVC=$comp
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------- 状态

show_status() {
    echo ""
    echo "=== 当前主题 ==="
    say "UUID     : $(run shell "settings get global applied_default_theme_package_name" | tr -d '\r')"
    say "主题版本 : $(run shell "getprop ro.oplus.theme.version" | tr -d '\r')"
    echo "=== /data/theme ==="
    run shell "ls -1 /data/theme 2>/dev/null" | tr -d '\r' | while read -r n; do
        [ -n "$n" ] && printf "  %s\n" "$n"
    done
}

# ---------------------------------------------------------------- 读取主题 UUID

theme_uuid() {
    _f="$1"
    if command -v unzip >/dev/null 2>&1; then
        unzip -p "$_f" themeInfo.xml 2>/dev/null | tr -d '\r' \
            | sed -n 's:.*<UUID>\([^<]*\)</UUID>.*:\1:p' | head -1
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import re,sys,zipfile;x=zipfile.ZipFile(sys.argv[1]).read("themeInfo.xml").decode("utf-8","replace");m=re.search(r"<UUID>([^<]*)</UUID>",x);print(m.group(1).strip() if m else "")' "$_f"
    else
        echo ""
    fi
}

# ---------------------------------------------------------------- 参数

detect_store || true

case "${1:-}" in
    ''|-h|--help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    --status)
        show_status
        exit 0
        ;;
esac

THEME=$1
[ -f "$THEME" ] || die "找不到主题文件：$THEME"
command -v "$ADB_BIN" >/dev/null 2>&1 || [ -x "$ADB_BIN" ] || die "找不到 adb（可用 ADB=/path/to/adb 指定）"

DEVS=$(run devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}')
[ -z "$DEVS" ] && die "没有已授权的设备。请打开 USB 调试并在手机上允许。"
say "设备：$(echo "$DEVS" | tr '\n' ' ')"

TARGET_UUID=$(theme_uuid "$THEME")
BEFORE_UUID=$(run shell "settings get global applied_default_theme_package_name" | tr -d '\r')

echo ""
say "主题：$(basename "$THEME")"
[ -n "$TARGET_UUID" ] && say "目标 UUID：$TARGET_UUID"
say "当前 UUID：$BEFORE_UUID"

if [ -n "$TARGET_UUID" ] && [ "$TARGET_UUID" = "$BEFORE_UUID" ]; then
    warn "当前已是该主题，系统不会重做（UUID 相同即视为已应用）"
    warn "如需强制重应用：先换 UUID（tools/newuuid.py），或先换成别的主题"
    exit 2
fi

# ---------------------------------------------------------------- 推送 + 投递

echo ""
say "推送 ..."
run push "$THEME" "$REMOTE" >/dev/null || die "推送失败"
run shell "appops set $PKG MANAGE_EXTERNAL_STORAGE allow" >/dev/null 2>&1
run shell "input keyevent KEYCODE_WAKEUP" >/dev/null 2>&1
run shell "am force-stop $PKG" >/dev/null 2>&1
sleep 1

[ -z "$SVC" ] && die "没找到主题商店的 ThemeApplyService（本工具只适用于 ColorOS 主题栈）"
say "投递 ...（$PKG）"
run logcat -c >/dev/null 2>&1
run shell "am startservice -n $SVC --es THEME_PATH $REMOTE" \
    | tr -d '\r' | grep -iE 'Starting|Error|Exception|denied' | sed 's/^/  /'

# ---------------------------------------------------------------- 等待

say "等待应用完成（最多 ${TIMEOUT}s）..."
i=0
RESULT=''
while [ "$i" -lt "$TIMEOUT" ]; do
    sleep 10
    i=$((i + 10))
    # ColorOS 的 OplusHansManager 会冻结 :applyTheme；adb shell 有 root 时可直接解冻
    run shell 'for f in /sys/fs/cgroup/apps/*/cgroup.freeze; do echo 0 > "$f" 2>/dev/null; done' >/dev/null 2>&1
    CUR=$(run shell "settings get global applied_default_theme_package_name" | tr -d '\r')
    printf '.'
    if [ -n "$TARGET_UUID" ] && [ "$CUR" = "$TARGET_UUID" ]; then RESULT=switched; break; fi
done
echo ""

CUR=$(run shell "settings get global applied_default_theme_package_name" | tr -d '\r')

# ---------------------------------------------------------------- 结果

echo ""
if [ "$RESULT" = 'switched' ]; then
    ok "应用成功：UUID 已切换为 $CUR"
elif [ -n "$TARGET_UUID" ] && [ "$CUR" = "$TARGET_UUID" ]; then
    ok "应用成功：UUID = $CUR"
elif [ "$CUR" != "$BEFORE_UUID" ]; then
    ok "UUID 已由 $BEFORE_UUID 变为 $CUR"
else
    warn "未确认成功（UUID 未变化）"
    warn "  1) 保持亮屏后重试一次（进程可能被 ColorOS 冻结）"
    warn "  2) 桌面图标未刷新：$ADB shell am force-stop com.android.launcher"
    exit 1
fi

show_status
echo ""
say "如需设置锁屏壁纸，用 tools/set_lock_wallpaper.ps1（或手机端 theme.sh --lock-only）"
