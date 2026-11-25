#!/system/bin/sh
# ColorOS 主题工具 · 手机端脚本
#
# 特权来源三选一，权限等价：
#   root        : su -c "sh theme.sh ..."
#   Shizuku     : rish -c "sh theme.sh ..."
#   adb         : adb shell "sh theme.sh ..."
#
# 用法:
#   sh theme.sh                          # 交互式选主题并应用（含锁屏壁纸）
#   sh theme.sh <theme 路径>             # 直接应用指定主题
#   sh theme.sh <path> --no-lock         # 只应用，不动锁屏
#   sh theme.sh <path> --desktop         # 锁屏和桌面都设为主题里的图
#   sh theme.sh --lock-only <path>       # 只设置锁屏壁纸
#   sh theme.sh --status                 # 查看当前主题
#   sh theme.sh --help                   # 显示本帮助

PKG=com.heytap.themestore
SVC="$PKG/com.nearme.themespace.services.ThemeApplyService"
LOCKPKG=com.keke.lockwall
TMP=/data/local/tmp
TIMEOUT=300

say()  { echo "  $*"; }
ok()   { echo "  [OK] $*"; }
warn() { echo "  [!]  $*"; }
die()  { echo "  [x]  $*"; exit 1; }

# ---------------------------------------------------------------- 特权身份

USE_SU=""
HAS_RISH=0
if command -v rish >/dev/null 2>&1; then
  rish -c true >/dev/null 2>&1 && HAS_RISH=1
fi

setup_root() {
  [ "$HAS_RISH" = "1" ] && return 0
  [ "$(id -u)" = "0" ] && return 0
  if command -v su >/dev/null 2>&1 && su -c id 2>/dev/null | grep -q 'uid=0'; then
    USE_SU=su; return 0
  fi
  if [ -f /data/adb/ksud ]; then
    ln -sf /data/adb/ksud "$TMP/ksu-su" 2>/dev/null
    chmod 755 "$TMP/ksu-su" 2>/dev/null
    if "$TMP/ksu-su" -c id 2>/dev/null | grep -q 'uid=0'; then
      USE_SU="$TMP/ksu-su"; return 0
    fi
  fi
  return 1
}

# 以当前可用的最高身份执行（root > su > shell）
asroot() {
  if [ "$HAS_RISH" = "1" ]; then rish -c "$1"
  elif [ "$(id -u)" = "0" ]; then sh -c "$1"
  elif [ -n "$USE_SU" ]; then $USE_SU -c "$1"
  else sh -c "$1"; fi
}

have_root() {
  [ "$HAS_RISH" = "0" ] && [ "$(id -u)" != "0" ] && [ -z "$USE_SU" ] && return 1
  return 0
}

# ---------------------------------------------------------------- 参数

MODE=apply
NOLOCK=0
DESKTOP=0
THEME=""

for a in "$@"; do
  case "$a" in
    --no-lock)   NOLOCK=1 ;;
    --desktop)   DESKTOP=1 ;;
    --lock-only) MODE=lock ;;
    --status)    MODE=status ;;
    -h|--help)   MODE=help ;;
    *)           [ -z "$THEME" ] && THEME="$a" ;;
  esac
done

# ---------------------------------------------------------------- 状态

do_status() {
  echo ""
  echo "=== 当前主题 ==="
  say "UUID      : $(settings get global applied_default_theme_package_name)"
  say "主题版本  : $(getprop ro.oplus.theme.version)"
  echo ""
  echo "=== 已应用模块 ==="
  if have_root; then
    for f in /data/theme/*; do
      [ -f "$f" ] || continue
      n=$(basename "$f")
      [ "$n" = "applying" ] && continue
      [ "$n" = "config" ] && continue
      sz=$(asroot "stat -c %s '$f'" 2>/dev/null)
      [ -n "$sz" ] && printf "  %-26s %8s KB\n" "$n" $((sz / 1024))
    done
  else
    warn "需要 root 才能读取 /data/theme"
  fi
  LOCKF=/data/system/users/0/wallpaper_lock
  if have_root && asroot "[ -f $LOCKF ]" 2>/dev/null; then
    ok "锁屏壁纸：已设置"
  else
    warn "锁屏壁纸：未单独设置（或需要 root 才能查询）"
  fi
}

# ---------------------------------------------------------------- 对齐

# 返回: 0 已改写 / 1 无需改动 / 2 缺少工具 / 3 不是主题包 / 4 处理失败
align_theme() {
  src="$1"; dst="$2"
  command -v zip   >/dev/null 2>&1 || return 2
  command -v unzip >/dev/null 2>&1 || return 2

  work="$TMP/theme_align"
  rm -rf "$work"; mkdir -p "$work" 2>/dev/null

  # 确保可读（部分目录只有 root 能读）
  if [ ! -r "$src" ]; then
    asroot "cat '$src'" > "$work/src.theme" 2>/dev/null
    src="$work/src.theme"
  fi

  unzip -p "$src" themeInfo.xml > "$work/themeInfo.xml" 2>/dev/null || return 3
  [ -s "$work/themeInfo.xml" ] || return 3

  unzip -l "$src" 2>/dev/null | awk 'NR>3 && NF>=4 {print $NF}' > "$work/entries.txt"

  add=""
  for m in icons com.android.launcher; do
    grep -qx "$m" "$work/entries.txt" || continue
    grep -q "name=\"$m\"" "$work/themeInfo.xml" && continue
    add="$add    <package name=\"$m\" version=\"001\" />\n"
  done
  [ -z "$add" ] && return 1

  printf "%b" "$add" > "$work/add.txt"
  awk -v addfile="$work/add.txt" '
    /<\/packageInfo>/ { while ((getline line < addfile) > 0) print line; close(addfile) }
    { print }
  ' "$work/themeInfo.xml" > "$work/themeInfo.new"

  # 关键：必须用改写后的 themeInfo.new，不能再用原文件
  [ -s "$work/themeInfo.new" ] || return 4
  mv "$work/themeInfo.new" "$work/themeInfo.xml" || return 4

  cp "$src" "$dst" 2>/dev/null || asroot "cp '$src' '$dst'"
  ( cd "$work" && zip -q "$dst" themeInfo.xml ) 2>/dev/null || return 4
  return 0
}

# ---------------------------------------------------------------- 缺声明检查

check_decl() {
  f="$1"
  have_icons=$(unzip -l "$f" 2>/dev/null | awk '{print $NF}' | grep -cx 'icons')
  decl_icons=$(unzip -p "$f" themeInfo.xml 2>/dev/null | grep -c 'name="icons"')

  if [ "${have_icons:-0}" -gt 0 ] && [ "${decl_icons:-0}" -eq 0 ]; then
    echo ""
    warn "该主题含 icons 内容，但 themeInfo.xml 没有声明它"
    warn "直接应用会导致桌面图标不被应用，并清掉已生效的图标模块"
    if [ -t 0 ]; then
      printf "  仍要继续吗？(y/N): "
      read -r ans
      case "$ans" in
        [yY]*) return 0 ;;
        *) die "已取消。建议先对齐：在 Termux 里 pkg install zip 后重跑，或在电脑上对齐。" ;;
      esac
    else
      die "已取消（非交互）。请先对齐：pkg install zip 后重跑，或在电脑上对齐。"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------- 应用

theme_uuid() {
  unzip -p "$1" themeInfo.xml 2>/dev/null | tr -d '\r' \
    | sed -n 's:.*<UUID>\([^<]*\)</UUID>.*:\1:p' | head -1
}

apply_theme() {
  f="$1"
  expect=$(theme_uuid "$f")

  # 先判断「已是当前主题」——必须在投递之前，否则服务已经在跑了
  cur0=$(settings get global applied_default_theme_package_name 2>/dev/null)
  if [ -n "$expect" ] && [ "$cur0" = "$expect" ]; then
    warn "当前已是该主题，系统不会重做（UUID 相同即视为已应用）"
    warn "如需强制重应用：用 tools/newuuid.py 换一个 UUID，或先换别的主题再换回来"
    return 0
  fi

  uid=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1)
  [ -z "$uid" ] && uid=10333

  prev_freezer=$(settings get global cached_apps_freezer 2>/dev/null)

  asroot "appops set $PKG MANAGE_EXTERNAL_STORAGE allow" >/dev/null 2>&1
  asroot "settings put global cached_apps_freezer disabled" >/dev/null 2>&1
  asroot "am force-stop $PKG" >/dev/null 2>&1
  sleep 1
  asroot "am startservice -n $SVC --es THEME_PATH '$f'" >/dev/null 2>&1 || warn "投递服务返回异常"

  [ -n "$expect" ] && say "目标 UUID : $expect"

  i=0
  while [ $i -lt $((TIMEOUT / 10)) ]; do
    i=$((i + 1))
    sleep 10
    # 只解冻该应用 uid 的 cgroup（ColorOS 的 OplusHansManager 会冻结 :applyTheme）
    if have_root; then
      for cf in /sys/fs/cgroup/apps/uid_${uid}/cgroup.freeze /sys/fs/cgroup/apps/uid_${uid}/pid_*/cgroup.freeze; do
        [ -f "$cf" ] && echo 0 > "$cf" 2>/dev/null
      done
    fi
    cur=$(settings get global applied_default_theme_package_name 2>/dev/null)
    printf "."
    if [ -n "$expect" ] && [ "$cur" = "$expect" ]; then break; fi
  done
  echo ""

  # 还原设置
  if [ "$prev_freezer" = "null" ] || [ -z "$prev_freezer" ]; then
    asroot "settings delete global cached_apps_freezer" >/dev/null 2>&1
  else
    asroot "settings put global cached_apps_freezer $prev_freezer" >/dev/null 2>&1
  fi

  cur=$(settings get global applied_default_theme_package_name 2>/dev/null)
  if [ -n "$expect" ] && [ "$cur" = "$expect" ]; then
    ok "应用成功（UUID 已切换）"
  else
    warn "未确认成功，当前 UUID: $cur"
    warn "保持亮屏后重试一次；或换 UUID 后重试"
  fi
}

# ---------------------------------------------------------------- 锁屏壁纸

set_lock() {
  f="$1"
  if ! pm list packages 2>/dev/null | grep -qx "package:$LOCKPKG"; then
    warn "未安装 lockwall.apk，跳过锁屏壁纸"
    return 1
  fi

  work="$TMP/themewp"
  rm -rf "$work"; mkdir -p "$work"
  unzip -p "$f" wallpaper > "$work/wallpaper.zip" 2>/dev/null
  [ -s "$work/wallpaper.zip" ] || { warn "主题里没有 wallpaper 条目"; return 1; }

  unzip -o "$work/wallpaper.zip" -d "$work/x" >/dev/null 2>&1
  img=$(find "$work/x" -type f \( -name '*.jpg' -o -name '*.png' \) 2>/dev/null | grep -i -E 'keyguard|lock' | head -1)
  [ -z "$img" ] && img=$(find "$work/x" -type f \( -name '*.jpg' -o -name '*.png' \) 2>/dev/null | head -1)
  [ -z "$img" ] && { warn "没找到壁纸图片"; return 1; }

  # 关键：Android 11+ 上 /data/local/tmp 与其它应用外部目录都读不到，
  # 必须放到 LockWall 自己的私有目录（需 root）或它自己的外部目录。
  place=""
  lockuid=$(dumpsys package "$LOCKPKG" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1)
  if have_root && [ -n "$lockuid" ]; then
    priv="/data/data/$LOCKPKG/files/lock.jpg"
    out=$(asroot "mkdir -p /data/data/$LOCKPKG/files && cp '$img' '$priv' && chown $lockuid:$lockuid '$priv' && chmod 600 '$priv' && stat -c %s '$priv'" 2>/dev/null)
    case "$out" in
      ''|*[!0-9]*) : ;;
      *) place="$priv" ;;
    esac
  fi

  if [ -z "$place" ]; then
    extdir="/sdcard/Android/data/$LOCKPKG/files"
    asroot "mkdir -p '$extdir' && cp '$img' '$extdir/lock.jpg' && chmod 644 '$extdir/lock.jpg'" >/dev/null 2>&1
    place="$extdir/lock.jpg"
  fi
  [ -z "$place" ] && { warn "图片投放失败"; return 1; }

  extra=""
  [ "$DESKTOP" = "1" ] && extra="--ez desktop true"
  asroot "am start -n $LOCKPKG/.Main --es path '$place' $extra" >/dev/null 2>&1
  sleep 4

  # 校验：必须确认用的是指定文件，而不是内置图
  used_asset=0
  used_file=0
  if command -v logcat >/dev/null 2>&1; then
    if logcat -d -t 400 2>/dev/null | grep -q 'LockWall.*from=asset'; then used_asset=1; fi
    if logcat -d -t 400 2>/dev/null | grep -q 'LockWall.*from=file:'; then used_file=1; fi
  fi
  if [ "$used_asset" = "1" ] && [ "$used_file" = "0" ]; then
    warn "LockWall 读不到指定文件，已回退内置图（锁屏不会变成你选的那张）"
    return 1
  fi

  if have_root && asroot "[ -f /data/system/users/0/wallpaper_lock ]" 2>/dev/null; then
    ok "锁屏壁纸：已设置"
  else
    warn "锁屏壁纸：未确认（请自行锁屏确认）"
  fi
  rm -rf "$work"
}

# ---------------------------------------------------------------- 交互式选主题

pick_theme() {
  LIST="$TMP/theme_list.txt"
  : > "$LIST" 2>/dev/null
  for f in /sdcard/Download/*.theme /sdcard/Download/*.hwt /sdcard/*.theme; do
    [ -f "$f" ] && echo "$f" >> "$LIST"
  done

  n=$(wc -l < "$LIST" 2>/dev/null | tr -d ' ')
  if [ -z "$n" ] || [ "$n" = "0" ]; then
    warn "没找到主题文件，请把 .theme 放到 /sdcard/Download/"
    return 1
  fi

  echo ""
  echo "=== 可选主题 ==="
  i=0
  while read -r f; do
    i=$((i + 1))
    printf "  [%d] %s\n" "$i" "$f"
  done < "$LIST"
  echo "  [0] 退出"
  printf "  请输入序号: "
  read -r sel

  case "$sel" in
    ''|0) THEME=""; return 1 ;;
    *) THEME=$(sed -n "${sel}p" "$LIST") ;;
  esac
  [ -n "$THEME" ] && ok "已选择：$(basename "$THEME")"
  return 0
}

# ---------------------------------------------------------------- 主流程

case "$MODE" in
  help)
    awk 'NR>1 { if ($0 ~ /^#/) { sub(/^# ?/,""); print } else exit }' "$0"
    exit 0 ;;
  status)
    setup_root >/dev/null 2>&1
    do_status
    exit 0 ;;
esac

if [ -z "$THEME" ] && [ "$MODE" = "apply" ]; then
  pick_theme
fi
[ -z "$THEME" ] && die "未选择主题"
[ -f "$THEME" ] || die "找不到文件：$THEME"

setup_root || warn "未取得 root：以 shell 身份运行（投递服务可以成功，但无法解冻/读模块列表）"

echo ""
echo "=== 主题工具（手机端）==="
say "文件：$(basename "$THEME")  $(( $(stat -c %s "$THEME" 2>/dev/null || echo 0) / 1024 / 1024 )) MB"

READABLE="$THEME"
if [ ! -r "$READABLE" ]; then
  asroot "cp '$THEME' $TMP/theme_readable.theme && chmod 644 $TMP/theme_readable.theme" >/dev/null 2>&1
  READABLE="$TMP/theme_readable.theme"
  say "已拷贝到 $READABLE"
fi

if [ "$MODE" = "lock" ]; then
  set_lock "$READABLE"
  exit 0
fi

# 对齐（有 zip 才能做）
if command -v zip >/dev/null 2>&1; then
  say "检查模块声明 ..."
  ALIGNED="$TMP/theme_aligned.theme"
  align_theme "$READABLE" "$ALIGNED"
  case $? in
    0) ok "已补全缺失的模块声明"; READABLE="$ALIGNED" ;;
    1) say "声明完整，无需改动" ;;
    2) warn "缺少 zip/unzip，跳过对齐" ;;
    3) warn "不是 ColorOS 主题包（缺少 themeInfo.xml），继续尝试应用" ;;
    *) warn "对齐失败，用原包继续" ;;
  esac
else
  warn "设备上没有 zip，跳过模块对齐"
  warn "图标可能不生效。解决办法：Termux 里 pkg install zip 后重跑，或在电脑上先对齐"
fi

echo ""
say "开始应用（约 2~5 分钟，请保持亮屏）..."
check_decl "$READABLE"
apply_theme "$READABLE"

if [ "$NOLOCK" = "0" ]; then
  echo ""
  set_lock "$READABLE"
fi

echo ""
do_status
echo ""
ok "完成"
