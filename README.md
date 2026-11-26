# Android 主题工具

把本地主题包直接塞进手机：支持 ColorOS 的 `.theme`、小米的 `.mtz`、华为的 `.hwt` 和 vivo 的 `.itz`。不用改包，不用重签，也不用装什么框架。

插上数据线，敲一行命令就行，它会自己看手机型号走对应的路子：

```powershell
.\tools\theme_cli.ps1 apply -Theme .\主题.theme
```

懒得碰命令行？直接双击 `主题工具.bat`，或者把主题文件往它图标上一拖一松手，效果一样。

---

## 它能帮你干点啥

核心当然是**整包应用**。在 ColorOS 上，它会直接调用主题商店的投递服务，相当于替你在手机上点了那一下「应用」。动手之前还会顺手帮你修一下模块声明——很多民间主题包里明明塞了 `icons/`，却忘了在 `themeInfo.xml` 里写明，不补上这一步，套完主题图标根本不会变。

除了直接套用，日常折腾主题用得上的小功能也顺手塞进去了：

- **拼装混搭**：觉得 A 主题整体好看，但更喜欢 B 主题的图标？抽出来拼一起就行：
  ```powershell
  .\tools\theme_cli.ps1 apply -Theme .\底包.theme -Mix 'icons:D:\别的主题.theme'
  ```
- **只要其中几样**：只想换个图标和壁纸，别的保持系统默认：
  ```powershell
  .\tools\theme_cli.ps1 apply -Theme .\完整.theme -Only icons,wallpaper
  ```
- **装前先体检**：不管是 `.theme`、`.mtz`、`.hwt` 还是 `.itz`，先查一遍版本对不对、声明和实际文件对不对得上，省得装完翻车：
  ```powershell
  .\tools\theme_cli.ps1 check -Theme .\主题.theme
  ```
- **后悔药（需 root）**：怕把系统主题搞乱，应用前先给 `/data/theme` 拍个快照，不对劲随时退回去：
  ```powershell
  .\tools\apply_local_theme.ps1 -Backup
  .\tools\apply_local_theme.ps1 -Restore
  ```
- **强制重装**：同一个主题改了一点东西想重新应用，系统往往因为 UUID 没变直接装死。用 `tools/newuuid.py` 给它换个新身份证，就能逼着系统重来一遍。
- **单拆素材**：只想把包里的壁纸、图标、字体、铃声扒出来自己用？直接拆。这步跟手机品牌没关系，扒出来的图谁都能设成壁纸。
- **盯梢防回滚**：装完怕过几个小时被系统偷偷打回原形，可以挂个脚本盯着看：
  ```powershell
  .\tools\watch_theme.ps1 -Minutes 30
  .\tools\watch_theme.ps1 -Reboot -Minutes 5
  ```

---

## 实话实说：各家手机到底能用到哪一步

**ColorOS（OPPO / 一加 / realme）是真跑通的。**
我自己拿一加 9 Pro 测的（ColorOS 16，主题商店 17.11.7，uxdesign 16.1.3）。来回试了好几轮，重启了三次，放了十三个小时，主题依然稳稳当当。上面列的所有功能都能正常用。

**小米 / 澎湃、华为、荣耀、vivo 目前只能帮你走到一半。**
这四家的系统没有对外暴露可用的应用接口，做不到命令行一步到位。工具能干的活是探测机型、做包体检，然后把文件推到商店能扫到的目录，最后还得你自己在手机商店里点几下：

- **小米 / 澎湃**：推到 `/sdcard/Download/`，去主题商店走「本地导入」
- **华为**：推到 `/sdcard/Huawei/Themes/`
- **荣耀**：第三方主题要用鸿蒙的 `.hwt`，按 MagicOS 版本选
- **vivo**：推到 Download，去 i主题 里选「本地主题」

**提前打个预防针**：这四个平台的逻辑写了、单元测试也过了，但**没在真机上实际跑过**。先别把它们当成“已完美支持”，遇到问题欢迎提。

---

## 动手前先看这几条

**环境准备**：手机开 USB 调试，电脑装好 `adb`。如果想自动补全模块声明，电脑上得有 Python 3.8+（没有也能硬跑，就是图标可能不生效）。root 不是必须的，有的话能帮你自动解冻相关进程，也能用上面的快照备份。

**小米用户务必看一眼**：按主题作者的官方说明，MIUI 11/12/12.5 必须用 2026-01-11 之后打包的主题，否则可能直接开不了机；MIUI 12/12.5 硬刷 MIUI 13 以上的主题更是 100% 无限重启。这条我已经写死在 `check_package.ps1` 里了，它会读取你的 MIUI 版本和包内时间戳，一旦撞上直接红字拦下来。

**目前不管的事**：
- 只处理标准的 ROM 主题包。商店下载下来那种带 `resources/ descriptions/ previews/` 结构的 inner 包走的是另一套逻辑，暂时不支持。
- 单独换字体、单独换铃声也不支持，系统里那是独立入口。
- 平板、折叠屏、海外版 ROM 都没测过，表现不保证。

---

## 背后是怎么跑起来的

简单聊聊原理，免得大家用着心里没底。

ColorOS 的主题商店导出了一个叫 `ThemeApplyService` 的服务，靠 `signature` 级权限拦着普通 App——但巧了，`adb shell` 和 root 天生就有这权限。所以工具干的事其实很朴素：把包推到设备能读的地方，借 shell 的身份去敲这个服务的门，剩下的脏活累活全交给系统自己干。

真正往磁盘写东西的是 `com.oplus.uxdesign`。它会把各个模块解开落进 `/data/theme`，最后把 `applied_default_theme_package_name` 改成主题的 UUID。判断成没成功我不看 logcat（系统日志刷得太快，动不动就把关键信息冲没了），直接盯这个 UUID 变没变，最靠谱。

顺带提几条我试过但走不通的死胡同，省得后来人白费劲：重签主题包会丢掉全部签名权限，装了也白装；直接往 `/data/theme` 里硬拷文件，商店压根不认账；手动去改商店的数据库也没用，那是 App 私有库。

至于其他品牌为什么没法一步到位，排查过程和证据都记在 `docs/BRANDS.md` 和 `docs/VENDOR-FINDINGS.md` 里了。

代码结构分了两层：`tools/adapters/` 下面一个平台一个适配器，专管机型探测和包体检；`tools/theme_cli.ps1` 是统一入口，看探测结果自动调度。以后想适配新品牌，照着往里加一个适配器文件就行。

---

## 更多文档

- `docs/USAGE.md` — 详细用法，包含五种上手姿势、排错和回滚
- `docs/BRANDS.md` — 各大品牌和子品牌到底用的哪套主题栈
- `docs/VENDOR-FINDINGS.md` — 拆解 MIUI / 华为 / vivo 真包得出的结论
- `docs/ANALYSIS.md` — ColorOS 这条链路的完整逆向笔记
- `docs/STABILITY.md` — 系统里到底是谁会把你的主题偷偷改回去
- `docs/ADB.md` — 嫌脚本太重？这里有只要 4 条 adb 命令的极简版

---

MIT 协议。如果这个小工具替你省下了几个小时折腾的工夫，顺手点个 Star 就挺开心了。
