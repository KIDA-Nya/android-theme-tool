# ColorOS 本地主题应用工具

把本地的 `.theme` 主题包应用到 ColorOS（OPPO / 一加 / 真我）系统上。

**不改包、不重签、不需要 LSPosed。** 原理是直接调用系统自带的主题商店服务，
等价于在商店里点「应用」。

> 实测环境：一加 LE2123（ColorOS 16 / Android 16，`ro.oplus.theme.version=16000`）。
> 其它 ColorOS 12+ 机型原理相同，但未逐一验证。

---

## 它解决什么问题

ColorOS 的主题商店只认特定格式的包，第三方主题（尤其是没在商店上架的 ROM 主题包）
往往无法通过正常入口应用。常见的几种做法各有代价：

| 做法 | 问题 |
|---|---|
| 重写一个 App | 投递系统服务需要 `signature` 级权限，普通 App 拿不到，只能做「管理器」换不了主题 |
| 改 dex 后重签 | 换签名会导致 `OPPO_COMPONENT_SAFE` 等签名权限全部丢失，反而更用不了 |
| LSPosed Hook | 需要装框架、要重启，且部分机型取不到 Shizuku 依赖 |

本项目采用最短路径：**原版商店保持不动（签名与权限都在），用 shell 身份调用它的 exported 服务。**

---

## 原理

```
本地 .theme
   │ adb push 到设备
   ▼
am startservice  ThemeApplyService  --es THEME_PATH <path>
   │
   ├─ 校验主题包（需根级 themeInfo.xml）
   ├─ 比对 EditorVersion 与 ro.oplus.theme.version
   ├─ 逐个解包内嵌模块：wallpaper / com.android.systemui / settings / icons / launcher ...
   ├─ FileProvider 生成 URI + grantUriPermission("com.oplus.uxdesign", ...)
   ▼
com.oplus.uxdesign  UxThemeService（AIDL）
   ▼
/data/theme/{wallpaper, com.android.systemui, icons, ...}
settings global applied_default_theme_package_name = <主题 UUID>
```

详细逆向过程（含失败过的方案、错误码、冻结机制）见 [docs/ANALYSIS.md](docs/ANALYSIS.md)。

---

## 环境要求

| 项 | 说明 |
|---|---|
| 手机 | ColorOS 12+（`ThemeApplyService` 存在即可） |
| adb | 电脑侧需安装 Android Platform Tools；或用手机端 Termux |
| Python 3.8+ | 仅「声明对齐」用得到；加 `-NoAlign` 可跳过 |
| root | **可选**。有 root 能自动解冻进程、核对落盘模块；没有也能应用主题 |
| lockwall.apk | 可选，仅「设置锁屏壁纸」需要（可自行构建） |

可用环境变量覆盖自动探测：

```powershell
$env:THEME_ADB    = 'D:\platform-tools\adb.exe'
$env:THEME_PYTHON = 'C:\Python312\python.exe'
```

---

## 快速开始（电脑端）

```powershell
# 1) 手机开 USB 调试并授权
adb devices

# 2) 双击「主题工具.bat」，或用命令行
Set-ExecutionPolicy -Scope Process Bypass -Force
.\tools\apply_local_theme.ps1 -Theme '.\你的主题.theme'
```

菜单里有六项：

```
[1] 主题包体检（应用前建议先跑一次）
[2] 应用主题（自动含锁屏壁纸）
[3] 只设置锁屏壁纸
[4] 查看当前主题状态
[5] 恢复系统默认主题
[6] 按内容补齐缺失模块（需 root）
```

常用参数：

```powershell
.\tools\apply_local_theme.ps1 -Theme x.theme -Verify    # 只看状态
.\tools\apply_local_theme.ps1 -Theme x.theme -NoLock    # 不动锁屏
.\tools\apply_local_theme.ps1 -Revert                   # 恢复默认
```

---

## 快速开始（手机端，无需电脑）

```bash
# Termux 里执行一次
sh /sdcard/Download/setup.sh

# 之后只需
theme
```

`setup.sh` 会装好 Shizuku 的 `rish`、生成 `theme` 命令、配好 PATH。
没有 root 也能用（`rish` 就是 shell 身份）。详见 [docs/PHONE.md](docs/PHONE.md)。

---

## 遇到的坑（都已内置处理）

| 坑 | 现象 | 处理 |
|---|---|---|
| **模块声明缺失** | 主题里有 `icons` 但没声明 → 图标不生效，还会清掉已生效的图标模块 | 应用前自动「对齐」：扫描 zip 实际条目补全 `<packageInfo>` |
| **进程被冻结** | 卡住不动、没有 `apply success` | ColorOS 的 `OplusHansManager` 会冻结 `:applyTheme`；脚本持续把 `uid_xxx/cgroup.freeze` 写 0 |
| **同 UUID 空转** | 重复应用同一主题完全没反应 | 系统按 UUID 判定「已是当前主题」；可先切回默认，或用 `newuuid.py` 换 UUID |
| **存储不可读** | 应用日志 `EACCES` | 需 `appops set ... MANAGE_EXTERNAL_STORAGE allow` |
| **锁屏图不可读** | 日志 `from=asset`，锁屏没变 | `/data/local/tmp` 对普通应用不可读；改为写入应用私有目录 |
| **版本不匹配** | 中止在 `ThemeOSVersion is diff` | `EditorVersion` 必须等于 `ro.oplus.theme.version`，体检会提示 |

---

## 目录结构

```
.
├─ 主题工具.bat            Windows 双击入口（纯 ASCII，避免 cmd 编码问题）
├─ tools/
│  ├─ theme_console.ps1    交互式菜单
│  ├─ apply_local_theme.ps1  应用主题主流程
│  ├─ set_lock_wallpaper.ps1 设置锁屏壁纸
│  ├─ push_modules.ps1     直接补写 /data/theme（兜底）
│  ├─ build-lockwall.ps1   构建 LockWall APK
│  ├─ common.ps1           共享函数（adb/python 探测、安全执行、解冻）
│  ├─ theme_align.py       补全模块声明
│  ├─ check_theme.py       应用前体检
│  ├─ extract_keyguard.py  提取锁屏壁纸
│  └─ newuuid.py           换 UUID（强制重应用）
├─ phone/
│  ├─ theme.sh             手机端主脚本
│  └─ setup.sh             Termux 一次性安装
├─ lockwall/               LockWall 源码（壁纸小工具）
└─ docs/
   ├─ ANALYSIS.md          完整逆向分析
   └─ PHONE.md             手机端说明
```

---

## 构建 LockWall

```powershell
.\tools\build-lockwall.ps1 -Install
```

只用 SDK 自带命令行工具（`javac` → `d8` → `aapt2` → `zipalign` → `apksigner`），不需要 Gradle。

---

## 开发注意（编码坑）

这套脚本对文件编码很敏感，改动时请保持：

| 文件 | 要求 | 原因 |
|---|---|---|
| `*.ps1` | **UTF-8 带 BOM** + CRLF | Windows PowerShell 5.1 无 BOM 时按 ANSI 读取，中文会变乱码并导致语法错误 |
| `phone/*.sh` | UTF-8 无 BOM + **LF** | 设备上是 `/system/bin/sh`，CRLF 会让 `do`/`then` 解析失败 |
| `主题工具.bat` | **纯 ASCII** + CRLF | cmd 按 OEM 代码页解析批处理，UTF-8 中文必乱码 |

`.gitattributes` 已固定换行；`.bat` 保持 ASCII 是为了绕开代码页问题（用英文提示）。
PowerShell 里没有 `utf8NoBOM` 枚举，需要无 BOM 时用：

```powershell
[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
```

---

## 已知限制

- 只处理 **ColorOS ROM 主题包**（根级 `themeInfo.xml` + 内嵌模块 zip）；
  商店下载的 inner 格式（`resources/ descriptions/ previews/ keys/`）走的是另一条通道，不被支持。
- 只能整包应用；「只换图标 / 只换锁屏样式 / 字体 / 铃声」这类模块化应用尚未实现。
  相关逆向线索见 `docs/ANALYSIS.md` 的 `n9b` / `ThemeConfigInfo` 部分。
- 主题若不含锁屏资源，锁屏只能换壁纸，样式仍是系统默认。
- 系统 OTA 后 `ro.oplus.theme.version` 变化，老主题需改 `EditorVersion` 后重新打包。

---

## 免责声明

- 本项目仅用于**个人在自有设备上**使用自己拥有或获授权的主题资源。
- 主题包、壁纸、图标的著作权归原作者所有；请勿二次分发或商用。
- 修改系统主题属于非官方操作，请自行备份数据（`adb shell settings get/put`、
  `/data/theme` 均可能被重置）。使用风险自负。

## License

[MIT](LICENSE)
