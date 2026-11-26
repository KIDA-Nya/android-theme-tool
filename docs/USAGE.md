# 使用手册

按「你有多少耐心」从上往下挑一种即可。

| 方式 | 需要 | 操作量 | 适合 |
|---|---|---|---|
| **① 电脑 · 拖拽** | adb + Python | **把主题拖到 `.bat` 上，松手** | 最省事 |
| ② 电脑 · 菜单 | adb + Python | 双击 → 输序号 | 想先体检、看状态 |
| ③ 电脑 · 纯 adb | 只要 adb | 4 条命令 | 不想装 Python / 排查问题 |
| ④ 手机 · 桌面小组件 | Termux + Shizuku | **点一下图标** | 不用电脑 |
| ⑤ 手机 · `theme` 命令 | Termux + Shizuku | 输 `theme` 选序号 | 手机上有多个主题 |

---

## 0. 一次性准备

**手机**

1. 设置 → 关于手机 → 连点「版本号」7 次，开开发者选项
2. 开发者选项 → 打开「USB 调试」
3. 数据线连电脑，手机弹窗点「允许」（勾选「一律允许」更省事）

**电脑**

- `adb`：装 [Platform Tools](https://developer.android.com/tools/releases/platform-tools)，或设 `THEME_ADB` 指向它
- Python 3.8+：只影响「模块声明对齐」，没有也能跑（图标可能不生效）；或设 `THEME_PYTHON`
- root **不需要**。有 root 会更稳（自动解冻进程、核对模块）

**应用前先体检包**（`.theme` / `.mtz` / `.hwt` 通吃）

```powershell
.\tools\check_package.ps1 -Path '.\你的主题.theme'
```

会按平台自动选适配器，检查描述文件、版本门禁、声明与内容是否一致。

**换机型/换 ROM 先探测**

```powershell
.\tools\probe.ps1
```

逐项检查主题商店服务、权限、uxdesign、`/data/theme`、冻结控制，给出可用性结论。

**主题格式**

必须是 **ColorOS ROM 主题包**：根目录有 `themeInfo.xml`，模块以 zip 形式平铺存放。
商店下载的 inner 格式（`resources/ descriptions/ previews/ keys/`）不支持。

---

## 1. 电脑 · 拖拽（一键）

把 `.theme` 文件**拖到 `主题工具.bat` 的图标上**，松手即可。

等价的命令行写法：

```powershell
.\主题工具.bat "D:\主题\纳西妲.theme"
.\主题工具.bat "D:\主题\纳西妲.theme" -NoLock      # 不动锁屏
```

它会自动完成：体检 → 对齐声明 → 推送 → 授存储权限 → 关冻结 → 投递 → 轮询 → 还原设置
→ 核对模块 → 设置锁屏壁纸。

---

## 2. 电脑 · 菜单

双击 `主题工具.bat`（不带参数）：

```
[1] 主题包体检（应用前建议先跑一次）
[2] 应用主题（自动含锁屏壁纸）
[3] 只设置锁屏壁纸
[4] 查看当前主题状态
[5] 恢复系统默认主题
[6] 按内容补齐缺失模块（需 root）
[7] 指定主题文件路径…      ← 弹出文件选择框，选一次后续操作都用它
[8] 使用说明
```

选 `[7]` 后，菜单顶部会显示「已指定：xxx.theme」，之后的体检 / 应用 / 锁屏 / 补齐
都直接用这个文件；列表里也可以用 `P` 临时挑一个别处的文件。

主题文件放在下面任一位置会被自动列出：

```
<仓库根目录>/*.theme
<仓库根目录>/themes/*.theme
<仓库根目录>/build/*.theme
```

不在这些位置就选 `[0]` 手动输入路径（可以把文件直接拖进窗口）。

---

## 3. 电脑 · 纯 adb

不依赖任何脚本，见 [ADB.md](ADB.md)。四步：

```bash
adb push 主题.theme /sdcard/Download/theme_apply.theme
adb shell appops set com.heytap.themestore MANAGE_EXTERNAL_STORAGE allow
adb shell input keyevent KEYCODE_WAKEUP
adb shell am startservice -n com.heytap.themestore/com.nearme.themespace.services.ThemeApplyService \
  --es THEME_PATH /sdcard/Download/theme_apply.theme
```

封装版：`./tools/adb-apply.sh 主题.theme`（Git Bash / WSL / macOS / Linux）。

---

## 4. 手机 · 一次性安装

把 `phone/setup.sh`、`phone/theme.sh` 拷到 `/sdcard/Download/`，在 Termux 里跑一次：

```bash
sh /sdcard/Download/setup.sh
```

它会：装 Shizuku 的 `rish` 到 `~/bin`、生成 `theme` 命令、配 PATH、自检。

前提：Shizuku 已启动服务，并在其中打开「在终端应用中使用 Shizuku」。

---

## 5. 手机 · 桌面小组件（零输入）

装 `Termux:Widget` 后：

```bash
mkdir -p ~/.shortcuts
cp /sdcard/Download/widget.sh ~/.shortcuts/主题
chmod +x ~/.shortcuts/主题
```

长按桌面 → 小部件 → `Termux:Widget` → 选「主题」。

之后**点一下**就会应用 `/sdcard/Download/` 里最新的主题（含锁屏壁纸）。
想只换主题不动锁屏：把 `widget.sh` 里的 `--latest` 改成 `--latest --no-lock`。

---

## 6. 手机 · 命令

```bash
theme                     # 列出 Download 里的主题，选序号应用
theme --latest            # 直接应用最新的那个
theme --status            # 看当前主题
theme xxx.theme --no-lock # 指定文件，不动锁屏
theme --lock-only xxx.theme
```

交互列表里还有两个特殊项：

- `P` —— 打开文件选择器挑别处的主题（需装 Termux:API 的 `termux-api` 包；
  没装则退回手工输入路径）
- `0` —— 退出

---

## 7. 常见场景

| 我想… | 怎么做 |
|---|---|
| 换主题 | 拖拽 / 菜单 `[2]` / `theme` |
| 只换锁屏壁纸 | 菜单 `[3]`，或 `theme --lock-only xxx.theme` |
| 看现在用了什么 | 菜单 `[4]`，或 `theme --status` |
| 回到默认主题 | 菜单 `[5]` |
| 同一主题想重装一次 | 先换成别的主题再换回来；或 `python tools/newuuid.py 原.theme 新.theme` 后应用新文件 |
| 图标没变 | 先确认主题里确实有 `icons` 条目且已声明（菜单 `[1]` 体检会提示）；再 `adb shell am force-stop com.android.launcher` |
| 应用没反应 | 保持亮屏重试一次（进程被 ColorOS 冻结）；有 root 会自动解冻 |

---

## 7.5 混搭 / 只应用部分模块 / 备份恢复

### 先理解引擎的行为

ColorOS 的 `ThemeApplyService` **按"包里声明的模块集合"整体替换**，不是增量合并：

> 应用一个只声明了 `icons`、`wallpaper` 的包后，`/data/theme` 里就只剩这两项，
> 原来的 systemui / settings 等会被清掉（等于回到系统默认）。

实测记录（本机）：

```
只声明 icons + wallpaper 应用后
/data/theme → applying config icons wallpaper
```

所以两种需求要选对方式：

| 我想要 | 用哪个 | 结果 |
|---|---|---|
| 只改图标，其它**保持不变** | `-Mix icons:其它主题.theme` | 生成的包仍含全部模块，只换 icons |
| 只留图标，其它**回默认** | `-Only icons` | 包里只有 icons，其余被清掉 |

### 混搭（替换某个模块，其余不动）

```powershell
# 底包用完整主题，把 icons 换成另一个主题的
.\tools\apply_local_theme.ps1 -Theme '.\底包.theme' -Mix 'icons:D:\别的主题.theme'

# 同时换两个模块
.\tools\apply_local_theme.ps1 -Theme '.\底包.theme' -Mix 'icons:a.theme','com.android.systemui:b.theme'
```

只生成包不应用：

```powershell
python tools\theme_mix.py -o mixed.theme 底包.theme icons:别的.theme --dry-run
python tools\theme_mix.py -o mixed.theme 底包.theme icons:别的.theme --new-uuid
```

### 子集（只要某几个模块）

```powershell
.\tools\apply_local_theme.ps1 -Theme '.\完整.theme' -Only icons,wallpaper
```

### 备份与恢复（需 root）

```powershell
.\tools\apply_local_theme.ps1 -Backup     # 快照 /data/theme + 当前 UUID
.\tools\apply_local_theme.ps1 -Restore    # 用最新快照恢复
.\tools\apply_local_theme.ps1 -Restore -Snapshot '/sdcard/Download/theme_backup/theme-2026....tar'
```

快照落在 `/sdcard/Download/theme_backup/`，同时生成同名 `.json` 记录 UUID 与主题版本。
恢复时会：解包 → 改回 uxdesign 属主 → 同步 UUID 设置 → 重启桌面与 SystemUI 触发重载。

实测：

```
备份前 /data/theme: applying com.android.contacts com.android.launcher ... icons wallpaper
只应用 icons+wallpaper → /data/theme: applying config icons wallpaper
-Restore 后            → /data/theme: applying com.android.contacts ... icons wallpaper（8 项全回）
```

---

## 7.8 非 ColorOS 机型：拆资源 + 设壁纸

直接投递用不了，但可以"间接"用：

```powershell
# 1) 把包里的东西拆出来
python tools/extract_assets.py 主题包 -o 导出目录

# 2) 用其中一张图设壁纸（任意品牌都行，走 WallpaperManager）
.\tools\set_lock_wallpaper.ps1 -Image 导出目录\wallpaper\xxx.jpg
.\tools\set_lock_wallpaper.ps1 -Image 导出目录\wallpaper\xxx.jpg -Desktop
```

能拆的类别：`wallpaper`（壁纸）、`icons`（图标包）、`fonts`（字体）、`ringtone`（铃声）、
`ui`（模块 UI 素材，一般用不上）。

实测：ColorOS 主题拆出 3 张壁纸 + 473 个图标 + 325 个 UI 素材；
华为 `.hwt` 拆出 3 张壁纸 + 55 个图标 + 24 个 UI 素材。

注意：`-Desktop` 时系统会删掉 `wallpaper_lock`（锁屏跟随桌面），这是正常行为；
脚本会用像素比对确认是否真的写进去了。

---

## 8. 出问题怎么查

**先跑体检**（菜单 `[1]` 或 `python tools/check_theme.py 主题.theme --device-version <版本号>`），
它会直接告诉你包有没有问题。

看日志：

```bash
adb logcat -c
# ……重新应用一次……
adb logcat -d -s ApplyColorThemeFromOS12 TSpace.ApplyColorThemeFromOS12 ThemeApplyService
```

| 日志 | 含义 | 处理 |
|---|---|---|
| `EACCES` / `FileNotFoundException` | 商店读不到文件 | 补 `appops set … MANAGE_EXTERNAL_STORAGE allow` |
| `ThemeOSVersion is diff` | 版本不匹配 | 改主题 `EditorVersion` 为设备值 |
| `unzip package:xxx null` | 声明了但包里没有 | 正常，无害 |
| 没有 `apply success`，UUID 也没变 | 被冻结 / 同 UUID 空转 | 亮屏重试；或换 UUID |
| `applyThirdTheme failed! … code=` | uxdesign 侧失败 | 记录 code，多半是主题内容不合法 |

设备具体值：

```bash
adb shell getprop ro.oplus.theme.version        # 主题版本，如 16000
adb shell settings get global applied_default_theme_package_name   # 当前主题 UUID
adb shell ls -1 /data/theme                     # 已落盘模块
```

---

## 9. 回滚 / 卸载

| 想撤销 | 做法 |
|---|---|
| 主题 | 菜单 `[5]` 恢复默认，或系统设置里换回自带主题 |
| 电脑端工具 | 直接删仓库目录，无系统写入 |
| 手机端 `theme` 命令 | `rm ~/bin/theme ~/bin/rish*`，并从 `.bashrc` 删掉那行 PATH |
| LockWall | `adb uninstall com.keke.lockwall` |

工具不会改系统 APK、不改签名、不装框架，卸载即干净。
