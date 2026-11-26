# Android 主题工具

> 把手上的 `.theme` / `.mtz` / `.hwt` / `.itz` **真正装进手机**——不是解包看看，是让系统认。
> 一个命令，按你的机型自动选路径。

[![release](https://img.shields.io/github/v/release/KIDA-Nya/android-theme-tool?label=release)](https://github.com/KIDA-Nya/android-theme-tool/releases)
[![license](https://img.shields.io/github/license/KIDA-Nya/android-theme-tool)](LICENSE)
![platforms](https://img.shields.io/badge/platforms-ColorOS%20%7C%20HyperOS%20%7C%20MagicOS%20%7C%20OriginOS-1f6feb)
![verified](https://img.shields.io/badge/%E5%AE%9E%E6%9C%BA%E9%AA%8C%E8%AF%81-OnePlus%209%20Pro%20%C2%B7%20ColorOS%2016-2ea043)
![no-resign](https://img.shields.io/badge/%E4%B8%8D%E6%94%B9%E5%8C%85-%E4%B8%8D%E9%87%8D%E7%AD%BE-brightgreen)

```powershell
# 就这一条：自动识别机型，ColorOS 直接应用，其它平台自动转「交给商店」
.\tools\theme_cli.ps1 apply -Theme .\你的主题.theme
```

---

## 为什么会有这个项目

网上教人换主题的帖子，基本都卡在同一个地方：**主题商店不认你手上的包**。

已经试过、并且能证明走不通的路：

| 常见做法 | 为什么不行 |
|---|---|
| 写个 App 去投递 | 主题服务要 `signature` 级权限，普通 App 拿不到 |
| 改 dex 后重签 | 换签名会**丢掉全部签名权限**，装上反而更用不了（实测：`OPPO_COMPONENT_SAFE` 等 5 个权限全丢） |
| 直接往 `/data/theme` 拷文件 | 目录属主是系统组件，拷进去商店**不认这是"已应用"** |
| 手写商店数据库记录 | 记录在 App 私有数据库，`Android/data` 下那堆只是备份镜像 |

本项目的做法是**找系统自己的入口**：用 shell 身份调商店导出的投递服务，
等于替你点了「应用」。原版商店不动、签名不动、不装框架。

---

## 30 秒上手

**需要**：手机开 USB 调试 + 装了 `adb`；Python 3.8+（只用于模块声明对齐）；root 可选。

```powershell
.\tools\theme_cli.ps1 status                   # 先看看认不认得你的手机
.\tools\theme_cli.ps1 check  -Theme .\x.theme  # 应用前体检（推荐）
.\tools\theme_cli.ps1 apply  -Theme .\x.theme  # 应用
```

不想敲命令？双击 `主题工具.bat`，或者把主题文件**拖到 bat 图标上**松手。

---

## 支持哪些系统

| 平台 | 包格式 | 能做到 | 验证状态 |
|---|---|---|---|
| **ColorOS**（OPPO / 一加 / realme） | `.theme` | **整包应用**、混搭、子集、快照恢复 | ✅ 真机多次 + 重启 |
| **MIUI / HyperOS**（小米 / Redmi / POCO） | `.mtz` | 探测 + 体检 + 免 root 注入 Theme backup | ⚠️ 未真机 |
| **EMUI / HarmonyOS**（华为） | `.hwt` | 探测 + 体检 + 放 `Huawei/Themes` 交给商店 | ⚠️ 未真机 |
| **MagicOS**（荣耀） | `.hwt` / `.hnt` | 同上（第三方主题建议用鸿蒙 `.hwt`） | ⚠️ 未真机 |
| **OriginOS**（vivo / iQOO） | `.itz` | 探测 + 体检 + 放 Download 交 i主题 | ⚠️ 未真机 |

> 诚实标注：**只有 ColorOS 这条是实机验证过的**。其余平台是「按已知机制实现 + 有单元测试」，
> 没有真机跑过。每个平台的依据和边界都写在 [docs/BRANDS.md](docs/BRANDS.md)。

---

## 不只是"能应用"

| 能力 | 命令 | 说明 |
|---|---|---|
| 混搭 | `-Mix icons:别的.theme` | 从多个主题各取模块拼一个包，其它模块保持不变 |
| 子集 | `-Only icons,wallpaper` | 只留指定模块，其余回系统默认 |
| 备份 / 恢复 | `-Backup` / `-Restore` | 快照 `/data/theme`，翻车能回滚 |
| 换 UUID | `tools/newuuid.py` | 系统按 UUID 判"已是当前主题"，换掉才能强制重应用 |
| 包体检 | `check_package.ps1` | `.theme/.mtz/.hwt/.itz` 通吃，跨平台 |
| 资源提取 | `extract_assets.py` | 把壁纸/图标/字体/铃声从包里拆出来（三平台通用） |
| 稳定性观察 | `watch_theme.ps1 -Reboot` | 采样 UUID/模块，验证会不会被系统改回去 |

---

## 这些坑我都踩过，所以内置了处理

| 现象 | 真因 | 处理 |
|---|---|---|
| 图标不变 | 主题里有 `icons/` 但 `themeInfo.xml` 没声明 | 应用前自动扫描 zip 补全声明 |
| 卡住没反应 | ColorOS 冻结了 `:applyTheme` 进程 | 持续解冻 cgroup + 备份/还原系统设置 |
| 重复应用毫无反应 | UUID 没变，系统判定"已是当前主题" | 换 UUID，或先切回默认 |
| 锁屏没变 | 图片放在 `/data/local/tmp`，应用读不到 | 改投应用私有目录（这个坑踩了两次） |
| `EditorVersion` 不符 | 主题与系统版本不匹配 | 体检直接报出来 |

### ⚠️ 安全提醒（MIUI 用户必读）

主题作者的官方教程明确写着：

> MIUI 11/12/12.5 必须用 **2026-01-11 之后**的主题包，否则**可能导致设备无法开机**；
> MIUI 12/12.5 套用 MIUI 13+ 的主题会**无限重启（100% 复现）**。

`check_package.ps1` 已经内置这条检查，命中会红字警告。**别跳过体检。**

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/USAGE.md](docs/USAGE.md) | 使用手册：五种上手方式、场景对照、排错、回滚 |
| [docs/BRANDS.md](docs/BRANDS.md) | 品牌/子品牌矩阵（realme、Redmi、iQOO、荣耀、魅族、三星…） |
| [docs/VENDOR-FINDINGS.md](docs/VENDOR-FINDINGS.md) | 对 MIUI / 华为 / vivo 的真包实测记录 |
| [docs/ANALYSIS.md](docs/ANALYSIS.md) | ColorOS 的完整逆向分析（含被证伪的方案） |
| [docs/STABILITY.md](docs/STABILITY.md) | 长期稳定性：谁会把你主题改回去 |
| [docs/GUIDE-COMPARISON.md](docs/GUIDE-COMPARISON.md) | 与社区主流教程的逐平台对照 |
| [docs/ADB.md](docs/ADB.md) | 只用 4 条 adb 命令的最小流程 |

---

## 环境要求

- **adb**：装 [Platform Tools](https://developer.android.com/tools/releases/platform-tools)，或设 `THEME_ADB` 指向它
- **Python 3.8+**：只影响「模块声明对齐」，没有也能跑（图标可能不生效）；或设 `THEME_PYTHON`
- **root**：可选。有 root 更稳（自动解冻、快照备份、核对模块）
- **PowerShell 5.1 / 7+**（Windows）；手机端另有 Termux 脚本

---

## 已知限制

- 只处理 **ROM 主题包**（ColorOS `.theme` / MIUI `.mtz` / 华为 `.hwt` / vivo `.itz`）；
  商店下载的 inner 格式（`resources/ descriptions/ previews/ keys/`）走另一条通道，不支持
- ColorOS 只能整包或按模块子集应用，**不能只换字体/铃声**（那是另一条通道）
- 平板 / 折叠屏：上游教程标注不适配，本项目同样未验证
- 海外 ROM：未验证（上游教程仅覆盖中国大陆版）

---

## 免责声明

- 仅供**个人在自有设备**上使用自己拥有或获授权的主题资源
- 主题、壁纸、图标的著作权归原作者；请勿二次分发或商用
- 修改系统主题属非官方操作，请自行备份。使用风险自负

## License

[MIT](LICENSE)

---

**如果这个项目帮你把主题装进去了**，点个 ⭐ 能让更多同样卡住的人搜到它——
这个领域的中文资料太散了，多一个人看到就少一个人踩「重签丢权限」那个坑。
