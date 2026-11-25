# 本地主题导入 ColorOS 系统 —— 分析结论与落地方案

> 设备：OnePlus LE2123 / ColorOS 16 (V16.1.0) / Android 16 / KernelSU(ReSukiSU) + ZygiskNext
> 样本：`com.heytap.themestore` v17.11.7 (versionCode 1711070)，HeyTap 官方签名
> 结论日期：2026-11-15

---

## 一、最终结论（一句话）

**既不需要重写 APK，也不需要改包重签，更不需要 LSPosed。**
原版主题商店的 `ThemeApplyService` 是 `exported` 的，且已持有全部签名级权限；
用 root 直接向它投递 `THEME_PATH`，即可完整复刻"商店内点击应用主题"的链路。

已在本机实测通过，应用自身日志输出：

```
W/ApplyColorThemeFromOS12: from OS12 applyThemeByPathInThread, apply success! code = 0
W/CommonApplyFlag_UxAidlHelper: callback onApplyResult ... code = 0
```

---

## 二、为什么"重写"和"改包重签"都被证伪

### 2.1 权限矩阵（实测）

| 通道 | 入口 | 权限 | 第三方能否持有 |
|---|---|---|---|
| 安装/应用 | `ThemeApplyService`（`:applyTheme`，action `com.nearme.themespace.applytheme`） | `oppo.permission.OPPO_COMPONENT_SAFE`（`prot=signature`） | ❌ |
| OS12+ 系统应用 | bind `com.oplus.uxdesign` / `UXTHEME_APPLY_SERVICE` | `com.oplus.permission.safe.SETTINGS` | ❌ 需特权 |
| 写系统主题状态 | `/data/theme`、`persist.sys.*` | `WRITE_SECURE_SETTINGS` 等 | ❌ |

原包签名：`CN=HeyTapTeam, O=HeyTap, heytap@heytap.com`
→ 这些 `prot=signature` 权限是**靠这个签名**拿到的，与包名无关。

### 2.2 重签实测结果

我们完整走了一遍"baksmali → 改 3 处门禁 → smali 回编译 → 重签 → 安装"：

| 步骤 | 结果 |
|---|---|
| 改 dex + 重签 + `adb install -r` | ✅ 安装成功（该 ROM 不强制签名校验） |
| 安装后权限 | ❌ `OPPO_COMPONENT_SAFE`、`safe.SETTINGS`、`WRITE_SECURE_SETTINGS`、`MOUNT_UNMOUNT_FILESYSTEMS`、`INSTALL_PACKAGES` **全部丢失** |
| 结论 | 重签后应用变成"没有特权的壳"，反而不能应用主题 |

### 2.3 当时改了哪三处门禁（供复核，不建议采用）

| # | 文件 | 原逻辑 | 改动 |
|---|---|---|---|
| 1 | `ThemeInstaller.smali` | `getBoolean("key_is_from_third_part", false)` → 为真则返回 `-104` | 把键名改成不存在的 `key_is_from_third_part_blocked`，使分支永不命中 |
| 2 | `resourcemanager/theme/a.smali` | `r()` 中 `if-eqz p2, :cond_52`（第三方→返回 `-5`） | 改为无条件 `goto :cond_52`，强制走「解包落盘」分支 |
| 3 | `resourcemanager/theme/a$a.smali` | `run()` 中 `EditorVersion` 与 `getThemeOsVersion()` 不等则中止 | `if-nez v4, :cond_a7` 改为 `goto :cond_a7`，跳过版本比对 |

结果：包能装上、能启动，但**签名级权限全部失效**，投递 `ThemeApplyService` 时被拒。
换句话说，改掉的三处门禁本来就不是真正的瓶颈，权限才是。

已回滚：安装包 SHA256 恢复为 `3ab0ad9f…`，权限已恢复，应用正常运行。

> 注：`/system_ext/etc/permissions/privapp-permissions-oplus-common.xml:821` 里确有
> `com.heytap.themestore` 的白名单条目，但该白名单只对 **priv-app 位置**生效，本应用在 `/data/app`。

---

## 三、实测成功的应用链路

```
本地 .theme
   │ adb push → /sdcard/Android/data/com.heytap.themestore/files/
   ▼
am startservice  ThemeApplyService  --es THEME_PATH <path>        (root 投递)
   │
   ├─ ThemeApplyService.f(path)  → 四个目录校验(resources/descriptions/previews/keys/)
   │       非 inner（ROM 主题包）→ false
   ▼
ApplyColorThemeFromOS12  (theme.b)   [isOS12: SDK>30 / ColorOS≥23 / theme.version≥12000]
   │
   ├─ zab.c(path) 解析根级 themeInfo.xml          (OplusSmartPhoneThemeInfo)
   ├─ EditorVersion vs ro.oplus.theme.version      ← 16000 == 16000 通过
   ├─ 逐个解包内嵌 zip：wallpaper / com.android.systemui / settings / mms / contacts
   ├─ vxb + FileUtils.getFileUri → fileProvider URI
   ├─ grantUriPermission("com.oplus.uxdesign", uri, FLAG_GRANT_READ)
   ├─ UxAidlHelper bind com.oplus.uxdesign / UXTHEME_APPLY_SERVICE
   ▼
uxdesign  IApplyManager.apply(uri, config)  →  IApplyCallback code = 0
   ▼
/data/theme/{wallpaper, com.android.systemui, ...}   (属主 u0_a307 = uxdesign)
settings global applied_default_theme_package_name = <主题 PackageName/UUID>
/data/system/users/0/wallpaper 被替换
```

### 关键字段

- 主题根级 `themeInfo.xml`：`PackageName`、`UUID`、`EditorVersion`、`VersionCode`、`IsGlobalTheme`、`packageInfo`
- 设备 `ro.oplus.theme.version = 16000`，必须与 `EditorVersion` 相等
- 应用记录：`/data/theme/applying/resRecord/resRecordConfig`（`sourceType: THEME_WHOLE`）
- `config`：`{"applyType":3, ...}`，3 = OS12 全量应用

---

## 四、两个坑（都已内置到脚本）

1. **存储权限**：把文件放 `/sdcard/Download/` 会 `EACCES` →
   必须 `appops set com.heytap.themestore MANAGE_EXTERNAL_STORAGE allow`，
   或放到应用自己的 `files/` 目录。
2. **Service 启动方式**：`am start-foreground-service` 会因服务未调 `startForeground()`
   在 5 秒后抛 `ForegroundServiceDidNotStartInTimeException` 崩溃 →
   必须用 `am startservice`。

---

## 五、交付物

| 文件 | 用途 |
|---|---|
| `tools/apply_local_theme.ps1` | 一键应用本地 `.theme`（`-Verify` 体检 / `-Revert` 恢复默认 / `-NoLock` / `-NoAlign`） |
| `tools/theme_console.ps1` | 交互式菜单（体检 / 应用 / 锁屏 / 状态 / 恢复 / 补齐） |
| `tools/check_theme.py` | 主题包体检：EditorVersion、声明与实际条目比对、锁屏资源 |
| `tools/theme_align.py` | 补全模块声明（扫描 zip 实际条目） |
| `tools/extract_keyguard.py` | 从 `wallpaper` 内嵌 zip 提取锁屏壁纸 |
| `tools/newuuid.py` | 换 UUID（规避「同 UUID 视为已应用」） |
| `tools/push_modules.ps1` | 直接向 `/data/theme` 补文件（兜底，需 root） |
| `tools/build-lockwall.ps1` | 构建 LockWall（javac/d8/aapt2/apksigner，无需 Gradle） |
| `phone/theme.sh` | 手机端脚本（root / rish / adb shell 三种身份） |
| `phone/setup.sh` | Termux 一次性安装（装 rish、生成 `theme` 命令） |

用法：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\tools\apply_local_theme.ps1 -Theme '.\你的主题.theme'
.\tools\apply_local_theme.ps1 -Verify
.\tools\apply_local_theme.ps1 -Revert
```

脚本会自动：校验 `themeInfo.xml` / `EditorVersion` → 对齐声明 → 推送 →
授存储权限 → 关冻结并备份原值 → `startservice` 投递 → 轮询（自动解冻）→
还原设置 → 输出系统主题状态 → 核对模块落盘。

---

## 六、非 root 可用性（已实测）

**可用。** 关键事实：`com.android.shell` 位于 `/system/priv-app/Shell`、带平台签名，
天然持有 `oppo.permission.OPPO_COMPONENT_SAFE`（虽然 `dumpsys` 的 shell 授权表里看不到，
但 AMS 放行，实测两次均成功）。

全链路无 root 验证通过：

| 动作 | 命令 | 结果 |
|---|---|---|
| 推送主题 | `adb push x.theme /sdcard/Download/` | ✅ |
| 授存储权限 | `adb shell appops set com.heytap.themestore MANAGE_EXTERNAL_STORAGE allow` | ✅ |
| 触发服务 | `adb shell am startservice … --es THEME_PATH …` | ✅ `apply success! code = 0` |

因此脚本默认走免 root 模式（`-Root` 仅为兜底）。

**不行的情况**：普通第三方 APK（非 shell/非平台签名）直接 startService 会被拒；
若要用 App 形态在非 root 设备上自动化，需借助 Shizuku（以 shell 身份执行同样命令）。

## 七、模块覆盖与"图标/锁屏"问题（已修正）

### 两条路径的行为差异（关键）

| 路径 | 模块识别方式 | 证据 |
|---|---|---|
| 商店 UI 应用流程 | **扫 zip 实际条目** | `apply/n9b` 构造 `ThemeConfigInfo$IconsDTO`，用 `BaseUtil.isBelongToModuleIcons(String)` 判定条目归属（`n9b:1658`、`n9b:2340`）；`theme/a:142` 另有专门 `"icons"` 分支 |
| `ThemeApplyService` 捷径（本项目用） | **按 `themeInfo.xml` 的 `<packageInfo>` 枚举** | `theme/b`（tag `ApplyColorThemeFromOS12`）逐个 `unzip package:<声明名>` |

→ 所以"图标不写声明也会导入"只在商店路径成立；捷径路径必须声明。
**已通过 `tools/theme_align.py` 移植对齐**：扫描真实条目反推完整 `packageInfo`（补 `icons`、`com.android.launcher`，并把 `systemui/settings` 版本扩到 `001,002`），使捷径结果与商店一致。

> **概念更正**：所谓"对齐"并非让系统按内容识别，而是把"扫内容的结果"写进声明。
> `theme/b.y()` 里 `gdb.m` 就是 `themeInfo.xml` 解析出的模块名列表，循环只做
> `zipFile.getEntry(name)`，全程不遍历 zip 条目。

### 真正"按内容"的两种做法

| 做法 | 是否需要改包 | 前提 | 说明 |
|---|---|---|---|
| 商店 `n9b` 通道 | 否 | 需在持 `safe.SETTINGS` 的进程里实现 AIDL 调用 | 最正宗，但工作量大 |
| **直接写 `/data/theme`** | **否** | root | 已实现为 `tools\push_modules.ps1`：读 zip 实际条目，把缺失模块写入 `/data/theme`，属主改为 uxdesign 的实际 uid（运行时探测），重启桌面刷新 |

因此本项目给了两条等价路线：
- **无 root/无 zip**：先用 `theme_align.py` 在电脑上对齐（改写声明）；
- **有 root**：应用后直接 `push_modules.ps1` 按内容补齐，主题包一个字节都不动。

### 实测结论（新包 64MB / UUID 000E2314…）

对齐后完整应用成功，`/data/theme` 全部刷新：

| 模块 | 大小 | 来源校验 |
|---|---|---|
| icons | 20,223,226 | = zip 内新包值 ✅ |
| com.android.launcher | 21,429 | ✅ |
| wallpaper | 556,369 | ✅ |
| com.android.systemui | 7,200,212 | ✅ |
| com.android.contacts / mms / settings | 3,982,587 / 4,418,650 / 4,843,228 | ✅ |

`applied_default_theme_package_name = 000E2314E15D492888EAE3790E20FF8F`（新主题 UUID）。

### 锁屏壁纸：此前判断有误，特此更正

- 本 ROM **没有独立锁屏壁纸文件**，`/data/system/users/0/` 只有 `wallpaper` / `wallpaper_orig`；
- 应用时走 `WS.WallpaperSetter.setDesktopWallpaper` → `WallpaperManager`，**桌面与锁屏共用同一壁纸**；
- `picture/res/drawable-xxhdpi/preview_lock.png`（1536×3072）只是商店详情页的**效果预览图**，不参与应用；
- 结论：**锁屏壁纸没有漏**；主题包里没有的仅是**锁屏样式/画报**类素材（lock 模块）。

### 锁屏壁纸：真正的缺口与解决办法（已实测）

**主题里其实有锁屏壁纸**，它藏在 `wallpaper` 条目的内嵌 zip 里：

```
res/drawable-xxhdpi/oppo_default_keyguard_wallpaper.jpg   205,043 B   ← 锁屏
res/drawable-xxhdpi/oppo_default_wallpaper.jpg            205,043 B   ← 桌面
res/drawable-xxhdpi/oppo_default_wallpaper.png            180,597 B
```

**但 OS12 应用路径（`theme/b`）只调 `WS.WallpaperSetter.setDesktopWallpaper`**，
`oppo_default_keyguard_wallpaper` 只在旧路径 `theme/a.C()` 里被使用（`ifc.m(...)`），
所以主题应用完成后桌面变了、锁屏没变。`preview_lock.png` 只是详情页效果图，与此无关。

**解决**：`tools/set_lock_wallpaper.ps1` —— 从 `.theme` 提取 keyguard 图，
用 `LockWall` 小工具（`WallpaperManager.setBitmap(..., FLAG_LOCK)`）写入。
实测写入后系统生成 `/data/system/users/0/wallpaper_lock`（此前不存在）。

```
.\tools\set_lock_wallpaper.ps1 -Theme 'xxx.theme'
.\tools\set_lock_wallpaper.ps1 -Theme 'xxx.theme' -Desktop    # 桌面也一起设
.\tools\set_lock_wallpaper.ps1 -Image 'C:\pic.jpg'
```

`LockWall` 工程在 `lockwall\`，构建链（aapt2 + javac + d8 + apksigner）已跑通，
图片以内置 asset 兜底，也支持 `--es path <可读路径>`（root 下 `/data/local/tmp/*.jpg` 最稳）。

## 八、进程冻结坑（务必保留此处理）

`:applyTheme` 进程会在打包完成后被 **`cached_apps_freezer` 冻结**（调用栈停在 `do_freezer_trap`），
此时它已 bind 上 uxdesign 但收不到回调，表现为"永远没有 apply success、`/data/theme` 不更新"。

处理（脚本已内置）：

1. `settings put global cached_apps_freezer disabled`（结束时恢复原值）
2. `input keyevent KEYCODE_WAKEUP` + `svc power stayon true`
3. root 兜底：把 `/sys/fs/cgroup/apps/uid_10333/**/cgroup.freeze` 写 `0` 解冻
4. 等待窗口设为 5 分钟（大主题打包 + uxdesign 处理需要 2~4 分钟）

**不要中途 `am force-stop`**——会把正在打包/应用的服务直接杀掉（退出原因 `USER REQUESTED / FORCE STOP`）。

## 九、重复应用同一主题会"空转"（重要）

系统以 `applied_default_theme_package_name`（= 主题 UUID）判断"是否已是当前主题"。
**当 UUID 相同而 `/data/theme` 内容不同（例如上次用了未对齐的包）时，服务不会真正重做**：
没有 `apply success`、模块不更新，表现像卡死。

变通办法（任一）：

1. 换一个主题再换回来（UUID 变化才会真正应用）；
2. 改主题 `themeInfo.xml` 里的 `UUID` / `PackageName` 为新值，重新打包后应用；
3. 有 root 时直接补写模块：
   ```bash
   adb push icons /data/local/tmp/icons
   adb shell su -c 'cp /data/local/tmp/icons /data/theme/icons'
   adb shell su -c 'chown u0_a307:u0_a307 /data/theme/icons'
   adb shell su -c 'chmod 777 /data/theme/icons'
   adb shell am force-stop com.android.launcher    # 刷新图标
   ```

> 判断是否真成功，只认日志 `apply success`；**不要**用 UUID 相等提前判定。

## 十、交付形态

| 端 | 入口 | 说明 |
|---|---|---|
| 电脑 | `主题工具.bat` | 双击菜单：体检 / 应用（自动含锁屏）/ 锁屏 / 状态 / 恢复 / 补齐 |
| 电脑 | `tools\*.ps1` | 命令行版本，可脚本化 |
| 手机 | `phone\theme.sh` | Termux + root 运行，功能同上（对齐需 `pkg install zip`） |
| 手机 | `phone\lockwall.apk` | 设锁屏壁纸的小工具 |

## 十一、局限与风险

- 依赖 root（KernelSU / ReSukiSU / Magisk 均可），脚本用 `ksud` 软链兜底 `su`。
- 依赖原版商店存在且未被替换（**不要**安装重签改包版，会丢权限）。
- 系统 OTA 升级后 `ro.oplus.theme.version` 会变，老主题的 `EditorVersion` 不匹配会中止，
  需同步修改主题里的 `EditorVersion` 后重新打包。
- 主题格式必须是 **ColorOS ROM 主题包**（根级 `themeInfo.xml` + 内嵌包 zip），
  不是商店下载的 inner 格式（`resources/ descriptions/ previews/ keys/`）。
- 回退：`-Revert` 或系统设置里切换默认主题；原包与数据备份均在 `build/` 下。
## 十二、免 root 的三条等效通道（已实测）

投递 `ThemeApplyService` 需要 `oppo.permission.OPPO_COMPONENT_SAFE`（`prot=signature`）。
普通 App 拿不到，但以下三种身份的权限等价，均可正常工作：

| 身份 | 取得方式 | 实测 |
|---|---|---|
| root（uid 0） | KernelSU / ReSukiSU / Magisk | OK |
| **shell（uid 2000）** | **Shizuku 的 `rish`**、或 adb shell | OK |
| 普通 App | — | 被 SecurityException 拒绝 |

免 root 实测（shell 身份，`sh theme.sh n.theme --no-lock`）：

```
  目标 UUID : B23CDFABF72C4D3886155A5299983984
..
  [OK] 应用成功（UUID 已切换）
```

能力边界：

| 能力 | shell（rish） | root |
|---|---|---|
| 应用主题 / 设锁屏壁纸 | 可以 | 可以 |
| 读 `/data/theme` 模块清单 | 不可以（SELinux） | 可以 |
| 按内容补写模块到 `/data/theme` | 不可以 | 可以 |

### 关于"做一个 Shizuku App"（已尝试，不推荐）

- `Shizuku.newProcess(...)` 在 api **13.1.5 被改为 private**，**13.0.0 / 12.1.0 仍是 public**；
- 但 `moe.shizuku.server.*`（`IShizukuService`/`IShizukuApplication`/`IRemoteProcess`）
  **不在 Maven 公开产物里**（`api`/`provider`/`shared` 三个 aar 均无），
  编译可过、运行必 `ClassNotFoundException`；
- 该 App 已从设备卸载，不作交付物。

结论：免 root 用 `rish` / `adb` 更省事；App 形态需走 Shizuku user service 或自写 AIDL transact，成本高于收益。
## 十三、图标"失效"的真正原因（已定位并修复）

### 现象
应用主题后桌面图标没变；即使 `/data/theme/icons` 文件存在，图标也不生效。

### 原因一：被未声明的包清掉了
`theme/b.y()` 只按 `themeInfo.xml` 的 `<package>` 声明逐模块解包。若应用一个**含 icons 但没声明**的包，
`icons` 会被跳过；同时 uxdesign 用它"本次应用应有的模块集合"覆盖 `/data/theme`，
于是**原有 icons 文件被删除**。

### 原因二：手动补文件不算"登记"
把 icons 文件直接拷进 `/data/theme` 后，文件在，但：

```
/data/theme/config        ->  "icons": []
resRecord/resRecordConfig ->  无 moduleType=icon
```

uxdesign 是按**应用记录**激活模块的，光有文件不会被当成已应用模块。必须走一次带声明的正常应用。

### 原因三：ColorOS 自己的冻结器让应用静默失败
`settings put global cached_apps_freezer disabled` **管不住 ColorOS 的 OplusHansManager**。
实测 `:applyTheme` 经常停在 `do_freezer_trap`，它已 bind 上 uxdesign 却收不到回调 →
日志无 `apply success`、`/data/theme` 不更新，表现为"卡住"。

判断：

```
$ cat /proc/<pid>/stack
[<0>] do_freezer_trap+0x5c/0xc4
$ cat /sys/fs/cgroup/apps/uid_10333/cgroup.freeze
1
```

解法（脚本已内置，uid 动态获取）：

```bash
echo 0 > /sys/fs/cgroup/apps/uid_$(stat -c %u /data/data/com.heytap.themestore)/cgroup.freeze
```

解冻后进程立刻从 `do_freezer_trap` 回到 `do_epoll_wait`，应用随即完成。

### 修复结果（实测）

解冻 + 应用带 `icons` 声明的包后：

```
UUID: 000E2314... -> B23CDFAB...
/data/theme: contacts/launcher/mms/settings/systemui/config/icons/wallpaper 全部 20:46 刷新
resRecord: "moduleType": "wallpaper" / "icon" / "lockscreen"   ← 图标模块已登记
```

结论：**图标要生效，必须让 uxdesign 自己走完一次带声明的应用**；
手动补文件只能"占位"，不能激活。