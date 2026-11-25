# 纯 adb 投递（不用任何脚本）

最小可用流程就 4 条命令，不需要 root、不需要 Python、不需要装任何东西（除了 adb）。

```bash
# 1) 把主题推到设备
adb push 你的主题.theme /sdcard/Download/theme_apply.theme

# 2) 让商店能读到这个文件（否则会 EACCES）
adb shell appops set com.heytap.themestore MANAGE_EXTERNAL_STORAGE allow

# 3) 亮屏（进程被冻结时会导致回调丢失）
adb shell input keyevent KEYCODE_WAKEUP

# 4) 投递
adb shell am startservice \
  -n com.heytap.themestore/com.nearme.themespace.services.ThemeApplyService \
  --es THEME_PATH /sdcard/Download/theme_apply.theme
```

约 10~30 秒后生效。验证：

```bash
adb shell settings get global applied_default_theme_package_name   # 应变成主题的 UUID
adb shell ls -1 /data/theme                                        # 应出现 wallpaper / icons / ...
```

也可以直接用脚本，逻辑与上面完全一致：

```bash
./tools/adb-apply.sh 你的主题.theme
./tools/adb-apply.sh --status
```

---

## 为什么是这 4 步

| 步骤 | 作用 | 不做会怎样 |
|---|---|---|
| `push` | 把文件放到设备 | — |
| `appops … MANAGE_EXTERNAL_STORAGE` | 授予「所有文件访问」 | 应用日志 `open failed: EACCES`，静默失败 |
| `KEYCODE_WAKEUP` | 亮屏 | `:applyTheme` 被 ColorOS 冻结，永远等不到回调 |
| `am startservice` | 投递 `THEME_PATH` | — |

关键点：**必须用 `am startservice`**。用 `am start-foreground-service` 会因该服务不调用
`startForeground()`，5 秒后抛 `ForegroundServiceDidNotStartInTimeException` 直接崩溃。

---

## 正常日志

```
D/ThemeApplyService: onStartCommand, sIsFrom911 = false, ..., themeFilePath=/sdcard/Download/theme_apply.theme
D/ThemeApplyService: os12 applying path = /sdcard/Download/theme_apply.theme
D/ApplyColorThemeFromOS12: 1 unzip package:wallpaper wallpaper
D/ApplyColorThemeFromOS12: 1 unzip package:com.android.systemui com.android.systemui
...
W/TSpace.CommonApplyFlag_UxAidlHelper: callback onApplyResult ... code = 0
W/ApplyColorThemeFromOS12: from OS12 applyThemeByPathInThread, apply success! code = 0
```

`unzip package:xxx null` 表示「声明了但包内没有这个模块」，无害。

---

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| 日志 `EACCES` / `FileNotFoundException` | 没给 `MANAGE_EXTERNAL_STORAGE` | 补第 2 步 |
| 一直没反应、没有 `apply success` | `:applyTheme` 被冻结 | 保持亮屏；有 root 时 `echo 0 > /sys/fs/cgroup/apps/uid_<uid>/cgroup.freeze` |
| 投递了但完全没反应，UUID 也没变 | 当前已是该主题（UUID 相同即视为已应用） | 换 UUID（`tools/newuuid.py`）或先换成别的主题 |
| 直接中止，日志 `ThemeOSVersion is diff` | 主题 `EditorVersion` ≠ 设备 `ro.oplus.theme.version` | 改主题里的 `EditorVersion` 重新打包 |
| 主题应用了但图标没变 | 主题含 `icons` 但 `themeInfo.xml` 没声明 | 用 `tools/theme_align.py` 对齐后重新投递 |

---

## 与 `apply_local_theme.ps1` 的区别

| | 纯 adb（本文） | `tools/apply_local_theme.ps1` |
|---|---|---|
| 依赖 | 只要 adb | 额外需要 PowerShell + Python |
| 模块声明对齐 | 不做（需手动跑 `theme_align.py`） | 自动 |
| 解冻 | 只做 best-effort | 按 uid 精确解冻 + 备份/还原系统设置 |
| 恢复默认主题 | 手动 `--es THEME_PATH Defult_Theme` | `-Revert` |
| 锁屏壁纸 | 不支持 | 自动跟随 |
| 模块落盘核对 | 不支持 | 支持 |

功能少但门槛最低——只想知道"到底怎么apply"的，用本文这 4 条命令即可。
