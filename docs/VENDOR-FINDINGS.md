# 厂商实证：MIUI / EMUI 主题机制的实测记录

本文记录**在没有对应设备的情况下**，通过取得真实安装包与真实主题包得到的结论。
所有结论都注明来源与获取方式，未验证的部分单独列出。

---

## 一、样本从哪来（含失败记录）

### 尝试过但被拦的渠道

| 渠道 | 结果 |
|---|---|
| `apkpure.com` / `d.apkpure.com` / `apkcombo.com` / `apkfab.com` / `apksum.com` / `apkmirror.com` | 全部 **403**（Cloudflare 拦截） |
| `memeosupdates.com` 的签名下载接口 `signed-link.php` | **403**（即使带同源 cookie 与 Referer） |
| 腾讯应用宝 `android.myapp.com` | 页面可达，但**未收录**该应用（重定向到 QQ） |
| 应用宝 / apkgk / apk-dl / apkbe | 无可直连的 APK |

### 最终取得的样本

| 样本 | 来源 | 说明 |
|---|---|---|
| `com.android.thememanager` 11.5.3.1（77 MB APK） | 开源项目 [HyperOS-MTZ-Studio](https://github.com/GloriousApps/HyperOS-MTZ-Studio) 的 `assets/xiaomi_themes_runtime_non_global_v2_0_0.zip` 内 `payload/theme.apk` | 真实 MIUI 主题管理器（community runtime 包内） |
| `theme.hwt`（6.6 MB，真实华为主题） | 开源项目 [iconapk2hwt](https://github.com/azzhu/iconapk2hwt) | 真实 `.hwt` 结构样本 |
| ThemeManager 桥接契约 | 同上，`ThemeManagerBridgeContract.java` | 社区补丁使用的 action/extras |

> 样本仅用于本地分析，**不进入仓库**（`.gitignore` 已排除 `_samples/`）。

---

## 二、MIUI / HyperOS：实测结论

`aapt2 dump badging` + `aapt2 dump xmltree` + `dexdump` 得到：

### 包信息

```
package   com.android.thememanager   versionCode 11531   versionName 11.5.3.1
minSdk 34   targetSdk 35   platformBuild 36（Android 16）
launchable-activity  com.android.thememanager.ThemeResourceTabActivity
provides-component 'wallpaper'
```

签名级权限（普通 App 拿不到，但说明它自己能做什么）：
`WRITE_SECURE_SETTINGS`、`SET_WALLPAPER`、`SET_LOCK_WALLPAPER`、`READ_WALLPAPER_INTERNAL`、`FORCE_STOP_PACKAGES`。

### 关键组件：**它确实有一个 exported 服务**

```xml
<service android:name="com.android.thememanager.service.ThemeService"
         android:permission="miui.permission.USE_INTERNAL_GENERAL_API"
         android:exported="true">
    <intent-filter>
        <action android:name="com.miui.service.THEMESERVICE"/>
    </intent-filter>
</service>

<service android:name="com.android.thememanager.service.ThemePCService"
         android:exported="true">
    <intent-filter>
        <action android:name="com.android.thememanager.service.IThemePCService"/>
    </intent-filter>
</service>
```

- `ThemeService` 继承 `miui.content.res.IThemeService$Stub`（**框架级 AIDL**）
- 该 build 里实现方法被混淆成短名（`n/p/s`(String)、`y`(String,Bitmap)），
  但 **framework 的 AIDL 定义是公开的**，见下节
- `ThemePCService` 是**电脑端工具**用的接口（`IThemePCService`）

> 这与 ColorOS 的结构**同构**：都是「exported 服务 + 签名级权限 + 系统执行者」。
> 差别在权限名（`miui.permission.USE_INTERNAL_GENERAL_API` vs `oppo.permission.OPPO_COMPONENT_SAFE`）。

### 真实资源路径（dex 字符串常量）

```
/data/system/theme/config.config
/data/system/theme/{fonts,lockscreen,ai_icon,aod,large_icons,rights,rearScreen,player_exo,debug_icon}/
/data/system/theme_magic/{ai_resource,maml_pag_temp,maml_web_temp,maml_sound_temp,maml_video_temp,users}/
/data/system/theme_staging        /data/system/theme_preview
/data/system/theme_region         /data/system/theme_dev
```

`description.xml` 也在 dex 里出现 → **确认 .mtz 内确有 description.xml**（此前只是推测）。

### 应用流程：in-process，不是对外 API

dex 里的类名说明应用是**应用内完成**的：

```
com.android.thememanager.util.ApplyThemeTask
com.android.thememanager.controller.local.ProvisionApplyTheme
com.android.thememanager.module.detail.presenter.ApplyThemeVM
com.android.thememanager.wallpaper.apply.BaseWallpaperApplyImpl.applyTheme
```

也就是说：**没有一个公开的「按路径应用主题」接口**。

### 社区是怎么做的

`HyperOS-MTZ-Studio` 的导入模块是 **Zygisk 模块**（`zygisk/arm64-v8a.so` + `dex/classes.dex`），
在主题管理器进程内注入桥接，然后用自己的 action 通信：

```
dev.glorioustr.mtzstudio.action.APPLY_MODERN_THEME
dev.glorioustr.mtzstudio.action.IMPORT_MODERN_THEME
  --es dev.glorioustr.mtzstudio.extra.THEME_PATH <path>
  --es …THEME_SHA256 …THEME_NAME
```

**这印证了**：MIUI 上想免 root 应用任意本地 `.mtz`，要么走 AIDL（权限待验证），
要么像社区那样 hook —— 不存在 ColorOS 那种「shell 一条命令投递」的等价物。

---

## 三、EMUI / HarmonyOS：实测结论

用真实 `theme.hwt`（6.6 MB）验证：

```
顶层条目：
  description.xml
  preview/                     （预览图，不参与应用）
  wallpaper/                   （4 项）
  unlock/                      （2 项，锁屏 MAML：unlock/theme.xml）
  icons/
  com.android.systemui/
  com.huawei.android.launcher/
```

`description.xml` 实测字段：

```xml
<HwTheme>
  <title>azzhu</title>
  <title-cn>朱</title-cn>
  <author>zqj</author>
  <version>5.0.5</version>
  <screen>FHD</screen>
</HwTheme>
```

结论：
- 根节点 `HwTheme`、`.hwt` 是 zip —— **与华为官方规范一致**，我的校验器判断正确
- 模块不只是 `wallpaper/icons/lockscreen`，还有 **`unlock/`（锁屏脚本）** 和
  **`com.huawei.android.launcher`**（桌面）
- 锁屏文件名是 `unlock/theme.xml`（不是某些资料说的 `unlock/lockscreen/manifest.xml`）

---

## 四、据此做的改动

| 文件 | 改动 |
|---|---|
| `tools/adapters/miui.ps1` | 探测改为检查 `ThemeService` 组件与 `miui.permission.USE_INTERNAL_GENERAL_API`；已知模块补 `aod/ai_icon/large_icons/rearScreen/player_exo/rights`；`ThemeDir` 标注实测来源 |
| `tools/adapters/emui.ps1` | 已知模块补 `unlock`/`com.huawei.android.launcher`/`com.huawei.android.mms`；新增锁屏 XML 检测并输出 `LockscreenXml` |
| `tools/check_package.ps1` | 输出 `LockscreenXml` 字段 |

真实样本复测：

```
[OK] theme.hwt   Root=HwTheme  title=azzhu  version=5.0.5
     KnownModules  icons, com.android.systemui, com.huawei.android.launcher, unlock, wallpaper
     LockscreenXml unlock/theme.xml
```

---

## 五、哪些已经查清、哪些还没

### 已经查清（有实证）

| 问题 | 结论 | 证据 |
|---|---|---|
| MIUI 的 AIDL 方法签名 | `saveWallpaper/saveLockWallpaper/saveIcon(String)`、`saveCustomizedIcon(String,Bitmap)` 共 4 个，无整包方法 | MIUI framework 反编译源码 + APK 里 4 个混淆方法一一对应 |
| 调用是否需要特权 | 社区实测：普通 App 直接 bind `ThemeService` 即可（通道 A），无需 root/Shizuku | HyperOS-MTZ-Studio 的分析与真机报告 |
| MIUI 免 root 能做什么 | 壁纸、锁屏壁纸、图标；**整包主题不行** | 同上，及其真机测试报告原话 |
| MIUI 资源路径 | `/data/system/theme/…`、`/data/system/theme_magic/…` | APK dex 字符串常量 |
| `.mtz` 是否有 description.xml | 有 | APK dex 中出现该常量 |
| 注入路线是否算免 root | **不算**——测试机已 root，且 `/data/adb`、`/proc/<pid>/maps` 对 shell 不可读 | 其真机报告明确声明 |
| EMUI 真实 hwt 结构 | 顶层 `description.xml/preview/wallpaper/unlock/icons/com.android.systemui/com.huawei.android.launcher` | 真实 `theme.hwt` 样本 |
| EMUI 锁屏文件 | `unlock/theme.xml`（MAML） | 同上 |

### 还没查清（需要设备或样本）

1. **真实 `.mtz` 的顶层目录清单** —— 手头没有 mtz 样本，当前模块名来自 dex 常量与公开资料。
2. **EMUI 的写入路径** —— `/data/themes/<id>/` 是公开资料说法，未在真机验证；
   也没找到 `com.huawei.android.thememanager` 的 APK 来做组件分析。
3. **EMUI 是否有等价的 exported 服务** —— 未取得 APK，未知。
4. **MIUI 通道 B 的细节** —— 写 `Android/data/com.android.thememanager` 后如何触发商店扫描，
   社区做法是「转成商店备份文件再恢复」，未在真机复现。

### 有真机/样本后怎么推进

```bash
# MIUI：确认通道 A 是否真的无需权限
adb shell dumpsys package com.android.thememanager | grep -A2 ThemeService
adb shell ls -ld /data/data/com.android.thememanager   # 需要 root
# 通道 B：看商店目录属组是否 ext_data_rw(1078)
adb shell ls -ld /sdcard/Android/data/com.android.thememanager

# EMUI：拿到 thememanager APK 后
aapt2 dump xmltree --file AndroidManifest.xml com.huawei.android.thememanager.apk | grep -i -B2 -A6 service
```

## 六、MIUI 到底能不能免 root 应用主题（已查到接口定义）

### 接口只有 4 个方法

来自 MIUI framework 的反编译源码
（[Fklearn/XiaomiFramework · IThemeService.java](https://github.com/Fklearn/XiaomiFramework/blob/master/mi2s_10_miui12/src/main/java/miui/content/res/IThemeService.java)）：

```java
public interface IThemeService extends IInterface {
    boolean saveLockWallpaper(String srcImagePath)  throws RemoteException;
    boolean saveIcon(String srcImagePath)           throws RemoteException;
    boolean saveWallpaper(String srcImagePath)      throws RemoteException;
    boolean saveCustomizedIcon(String fileName, Bitmap icon) throws RemoteException;
    // DESCRIPTOR = "miui.content.res.IThemeService"
}
```

这就解释了 APK 里看到的 `n/p/s(String)Z` + `y(String,Bitmap)Z` —— **正好 4 个**，
与上面的 `saveLockWallpaper / saveIcon / saveWallpaper / saveCustomizedIcon` 一一对应。

> **没有任何接受「主题包路径」的方法。** `ThemeService` 只能按路径设置**单项资源**
> （壁纸、锁屏壁纸、图标），不能应用整个 `.mtz`。

### 三条通道的实测结论

社区项目 [HyperOS-MTZ-Studio](https://github.com/GloriousApps/HyperOS-MTZ-Studio) 做过完整分析
（`docs/themes-3.4.8.36-rootless-analysis.md` 与 `docs/rootless-capability-device-test.md`），结论：

| 通道 | 做法 | 免 root 可行性 |
|---|---|---|
| **A** | 直接 bind `ThemeService`，调 `saveWallpaper/saveIcon` | ✅ 可行（无需任何特权），但**只能换壁纸和图标** |
| **B** | 把 `.mtz` 注册成商店的本地资源，用户手点「应用」 | ❌ 需要写 `Android/data/com.android.thememanager`，属组 `ext_data_rw`(gid 1078)，只有 **shell/Shizuku** 在组内，第三方 App 不在 |
| **C** | deep-link 把用户送到「应用」按钮（URI **fragment** 承载参数） | ✅ 可行，但最后一下仍要用户点 |

该报告的原话（针对无 root 设备）：

> "wallpapers and icons yes, a whole theme no"

并且明确指出：注入式方案（Zygisk）的测试机是**已 root** 的，
`/data/adb` 与 `/proc/<pid>/maps` 对 shell 都不可读，所以**注入路线不能算免 root 方案**。

### 与 ColorOS 的关键差异

| | ColorOS | MIUI |
|---|---|---|
| 整包应用接口 | ✅ `ThemeApplyService.apply(uri)` 接受主题路径 | ❌ 无 |
| shell 能否直接投递 | ✅ 能（本项目已实现） | ❌ 不能 |
| 免 root 能做多少 | 整包 | 壁纸 + 图标 |
| 整包要什么 | 无（shell 即可） | Shizuku 注册 + 用户手点，或 root/注入 |

**所以 MIUI 适配器不做写入是对的**——不是"没来得及实现"，而是接口层就不存在等价能力。

---

## 七、这次查证用到的检索方式（可复用）

```powershell
# 1) GitHub 代码搜索找接口定义
#    q=IThemeService filename:IThemeService.aidl
#    q=miui.content.res.IThemeService
#    命中：Fklearn/XiaomiFramework、XEonAX/ANXMiuiApps、munjeni/miui_v5_lotus

# 2) 取原始文件
#    https://raw.githubusercontent.com/<repo>/<branch>/<path>

# 3) 真实包结构
aapt2 dump badging  <apk>
aapt2 dump xmltree --file AndroidManifest.xml <apk>
dexdump -d <dex>            # 大 dex 输出可达 190MB，用脚本按需检索
```
## 八、如果接受 Shizuku 授权，小米能换主题吗？

**结论：Shizuku（ADB 模式）在小米这边几乎帮不上忙。** 这是真机测试出来的，不是推断。

测试机：2201116PG (veux)，Android 16 / HyperOS OS3.0.301.0，Themes 3.4.8.36-global，
无 su、无 root、无 Xposed、SELinux Enforcing。Shizuku/Shevery 跑在 **ADB 模式（uid 2000）**。

### 四条低层路线，全部对 uid 2000 关闭

| # | 路线 | 结果 |
|---|---|---|
| 1 | 用 MTZ Studio 自己的 BAK binder 恢复 | 代码里显式 gate：`SheveryBackupRestorer` 在 `Shizuku.getUid() != 0` 时返回 `ADB_ONLY` |
| 2 | 把 `.mtz` 直接丢进 Themes 的 `files/MIUI/theme/` | 无效——shell 确实在 `ext_data_rw` 组里能写进去，但商店本地列表不变 |
| 3 | 手写商店目录记录 `.data/meta/theme/<id>.mrm` | 无效——**目录在 App 私有数据库里**，`Android/data` 下那些文件只是备份镜像，不是真相源 |
| 4 | `content://` provider 查询 | **`SecurityException: requires miui.permission.USE_INTERNAL_GENERAL_API`** |

第 4 条特别重要：

```
content query --uri content://com.android.thememanager.theme_provider/theme
→ SecurityException: ... requires miui.permission.USE_INTERNAL_GENERAL_API
content query --uri content://com.android.thememanager.provider
→ SecurityException: ... (ThemeRuntimeDataProvider) same permission
```

也就是说：**`com.android.shell` 并不持有 `miui.permission.USE_INTERNAL_GENERAL_API`**（`signature|privileged`）。
这回答了上一版留下的疑问——那个 exported `ThemeService` 从 shell 侧调不动。

### 唯一免 root 可行的路：让系统 App 代劳

报告 §11 的突破不是"提权"，而是**找已在特权位置的系统应用**：

```
MTZ → 转成 MIUI 备份格式
    → 写 /sdcard/MIUI/backup/AllBackup/<ts>/
        Themes(com.android.thememanager).bak  +  descript.xml
      （需要 MANAGE_EXTERNAL_STORAGE，普通 App 就能申请）
    → 拉起 miui.intent.backup.LOCAL_HOME_ACTIVITY（exported，无权限）
    → 用户在 MIUI 备份里点「恢复」   ← 这一下由系统 App 用自己的权限完成
    → 商店目录出现记录 .data/meta/theme/<uuid>.mrm
    → deep link  ViewLocalResource://view.local.resource#<localId>
    → 用户在主题页点「应用」
```

2026-11-23 在无 root 真机上跑到 100% 完成，第三方主题成功进入目录并打开了自己的详情页。

### 但最后一关是内容 DRM

`miui.drm.DrmManager.isLegal(context, contentFile, rightsFile)` 按**主题内容**（不是 onlineId 字段）
算出一个 `<hash>.mra` 权利文件名，去 `.data/rights/theme/` 找，找不到就向小米下载（无权利时 413 失败），
应用被拦：

```
DrmService: check rights file: c010f94e...mra, exists: false
ThemeDebug:  CheckRightsTask return: DRM_ERROR_RIGHT_FILE_NOT_EXISTS
DrmService: downloadRights, resultCode=413
```

实验证明它是**按内容**判定的：
- 商店主题（Tokio，带真实 `.mra`）→ 点应用无效果，`isLegal` 失败
- 把记录的 `onlineId` / `productId` 改成 `null` → 恢复直接不产生记录（`DRM_ERROR_ASSET_NOT_MATCH`）
- 换成无权利文件、`onlineId:null` 的分享主题（Circle UI）→ 能进目录，但应用时**仍然**跑上面的 DRM 检查并被拦

所以：

| 主题类型 | 免 root 能否应用 |
|---|---|
| 真正原创、无 DRM 资产的组合 | **可以**（报告说这条与 DRM 按内容判定一致，但未端到端证明） |
| 商店主题 / 他人分享的受保护主题 | **不可以**，无免 root 绕过手段 |

### 那台"root 就能用"的机器是怎么回事

报告明确纠正了一个常见误解：能应用的那台 **klee** 装有 **LSPosed CorePatch**
（专门绕过 MIUI 签名/权利校验）。应用后 `/data/system/theme/rights` 是空的，
说明正是 CorePatch 中和了 `DrmService` 检查。**那不是"root 的功劳"，是 Xposed 模块的功劳。**

### 给你的项目的结论

1. **Shizuku ADB 模式对小米主题路径无增益**——四条低层路全关，签名权限 shell 拿不到。
2. **能落地的免 root 流程**是"备份 App 恢复 + deep link + 用户点两下"，且只对无 DRM 的主题有效。
3. **要稳定换任意第三方主题**，现实路径仍是 root + CorePatch 这类校验绕过；
   这与 ColorOS 不同——ColorOS 有合法的 exported 服务可调，小米没有。

---

## 九、小米主题商店自己是怎么「投递」的

反编译 `com.android.thememanager` 11.5.3.1 + MIUI framework 源码
（[Fklearn/XiaomiFramework · ThemeRuntimeManager.java](https://github.com/Fklearn/XiaomiFramework/blob/master/mi2s_10_miui12/src/main/java/miui/content/res/ThemeRuntimeManager.java)）
得到的完整链路：

```
Themes 进程（com.android.thememanager，普通应用 uid）
  │
  ├─ 1) DRM 校验        DrmManager.isLegal(ctx, contentFile, rightsFile)
  │       必须等于 DrmResult.DRM_SUCCESS 才继续，否则弹「下载权利失败」
  │
  ├─ 2) 备份当前主题    TrialBackupManager.n(...)
  │
  ├─ 3) 解包/准备资源   ApplyThemeTask → ThemeApplyUtils / ThemeFileUtils / ThemeZipFile
  │
  ├─ 4) 交给系统服务    ThemeRuntimeManager.bindService()
  │       context.getSystemService("security")        ← MIUI 的 security 服务
  │       再通过反射调用它的方法：
  │         saveIcon(String, Bitmap)
  │         setTheme / setThemeRes / setThemeType / setThemeUsingType
  │         markGadgetUpdated / restoreDefault
  │
  ├─ 5) 系统进程写盘    system_server（system uid）写：
  │         /data/system/theme/wallpaper
  │         /data/system/theme/lock_wallpaper
  │         /data/system/theme/boots/bootanimation.zip
  │         /data/system/theme/{fonts,lockscreen,icons,...}
  │         /data/system/theme/config.config
  │         /data/system/theme_magic/tempIcon/   （临时图标）
  │
  └─ 6) 通知全系统重载  ThemeResources.getSystem().resetIcons()
                        broadcast miui.intent.action.ACTION_THEME_CHANGED
                        （另有 ACTION_MMS_THEME_CHANGED）
```

### 关键点：真正写盘的是商店自己，不是 security 服务

**（此处修正早期判断）** 一开始看到 `ThemeRuntimeManager.bindService()` 拿
`getSystemService("security")`，以为是"商店把写盘交给安全服务"。继续读源码后结论不同：

**1) `security` 服务里根本没有 `setTheme`** —— 主题相关只有 `saveIcon`：

```java
// com/miui/server/SecurityManagerService.java
public void saveIcon(String fileName, Bitmap icon) { saveIconInner(fileName, icon); }
// 全文没有 setTheme / setThemeRes / setThemeType
```

（APK 里那几个 `setTheme*` 字符串不是调这个服务，是商店自己的主题记录/字段。）

**2) `saveIcon` 有硬身份校验，shell 过不去**：

```java
private boolean allowSaveIconCache() {
    return isSystemApp() && (UserHandle.getAppId(Binder.getCallingUid()) == 9801
                             || canSaveExternalIconCache());
}
private boolean isSystemApp() {
    int uid = Binder.getCallingUid();
    ...
    if ((pm.getApplicationInfo(pm.getPackagesForUid(uid)[0], 0).flags & 1) != 0) return true; // FLAG_SYSTEM
    return false;
}
```

要求调用者带 `FLAG_SYSTEM`（预装系统应用）。`com.android.shell` 不是系统应用，直接 false。

**3) 整包文件复制是商店进程自己做的直接 I/O**：

```
ThemeFileUtils.copySafety(...)
  → new File(path).canWrite()
  → miuix.core.util.FileUtils.zy(File src, File dst)    // 真实拷贝
  → new FileWriter(path)                                 // 写配置
```

也就是说：`com.android.thememanager` 是**平台签名 + 预装**的应用，运行在特权域里，
它自己就能读写 `/data/system/theme`，并不需要谁来"代写"。
`security` 服务只承担少数需要 system uid 的零碎操作（图标缓存等）。

**所以这条路对第三方是死的**：缺的不是"调用方式"，而是**平台签名与预装身份**。

这解释了四件事：

1. **为什么第三方 App 抄不了**：商店能写 `/data/system/theme` 是因为它**平台签名 + 预装**，
   运行在特权域里；第三方没有这个身份。`security` 服务同样要求调用者带 `FLAG_SYSTEM`。
2. **为什么 shell / Shizuku 也不行**：`shell`(uid 2000) 不是系统应用，
   `isSystemApp()` 直接 false；`USE_INTERNAL_GENERAL_API` 也不在它名下（第八节）。
3. **为什么 MIUI 备份能行**：`com.miui.backup` 是系统应用（`android.uid.backup`），
   它恢复时用的是它自己的系统权限，不是我们的。
4. **为什么"root 就行"是误解**：root 能写盘，但应用主题前那道 `DrmManager.isLegal`
   仍需绕过——那台机器靠的是 LSPosed CorePatch。

### 那能不能自己造一个"平台签名"的应用来调它？

不行。MIUI 的 `SecurityManagerService` 在 privileged 路径上直接比对平台签名：

```java
Signature[] platformSignature = pm.getPackageInfo("android", 64).signatures;
enforcePlatformSignature(platformSignature);
enforceAppSignature(platformSignature, "com.android.updater", true);
enforceAppSignature(platformSignature, "com.miui.securitycenter", false);
```

re-sign 只会让签名对不上（这与 ColorOS 上"重签丢权限"是同一个结局）。

### 与 ColorOS 的对照

| 环节 | ColorOS | MIUI |
|---|---|---|
| 谁发起 | 商店进程（`ThemeApplyService`） | 商店进程（`ApplyThemeTask`） |
| 校验 | `EditorVersion` 版本比对 | `DrmManager.isLegal` 内容 DRM |
| 交给谁执行 | `com.oplus.uxdesign`（`UxThemeService`，AIDL） | system_server 的 `security` 服务 |
| 外部能否触发 | ✅ 服务 exported，shell 有权限 | ❌ 服务不可达，shell 无权限 |
| 落点 | `/data/theme/` | `/data/system/theme/` |
| 通知 | uxdesign 内部重载 | `ACTION_THEME_CHANGED` 广播 |

结构上两家是**同一个套路**：应用进程只做校验与准备，真正写盘交给系统特权进程。
差别只在**入口是否对外开放**——ColorOS 开放了，MIUI 没有。

---

## 十、vivo / iQOO（OriginOS）：查到的事实与边界

没有真机，但找到了一个**高质量参考实现**：[VFont](https://github.com/SubmitCodes/VFont)
（Shizuku、免 root、在**国行 vivo X200 Ultra / OriginOS 7 上物理验证过**）。

### 包格式

来自其 [docs/themes.md](https://github.com/SubmitCodes/VFont/blob/main/docs/themes.md)：

> Import a local Vivo `.itz` under **Themes and wallpaper > Full themes**.
> Supported archives use **ZIP storage and root `description.xml`**; archive names, paths,
> sizes, XML, checksums and resource types are validated before native application.

即：**`.itz` = zip + 根级 `description.xml`**，和华为 `.hwt` 同构（只是根节点与字段不同）。
另有一条明确限制：

> Themes containing bundled fonts are rejected; choose fonts separately.

**自带字体的主题会被拒绝**——本项目适配器已把这条做成体检项。

### 目录与包名

| 项 | 值 | 来源 |
|---|---|---|
| 主题商店包名 | `com.bbk.theme`（i主题） | XDA 讨论、多个社区教程 |
| 外部数据 | `/sdcard/Android/data/com.bbk.theme/`（`download/`、`files/.dwd`、`theme/lockscreen/` 等） | 同上 |
| 核心存储 | `/data/bbkcore/theme/`（需 root） | 社区注入教程（利用文件管理目录穿越写入 `.dwd` 下） |

### 为什么本项目不做写入

VFont 的 [how-it-works](https://github.com/SubmitCodes/VFont/blob/main/docs/how-it-works.md) 写得很清楚：

> VFont **discovers the required Vivo backup interface signatures and transaction IDs from
> the installed framework**. It verifies stock UpSlide's identity, required features and
> current state before dispatching a fixed bounded worker **as system UID 1000**.

也就是说 vivo 的写入通道是**框架里的私有 Binder**，需要：
1. 从设备的框架里反查接口签名与 transaction id（每个版本可能不同）
2. 以 **system uid 1000** 派发（不是 shell 2000）
3. 并且按其兼容性说明，只对特定机型/ROM 有效

这不是"写个脚本"能覆盖的，且**我没有 vivo 真机**，无法验证任何一步。所以适配器只做只读。

### 本项目对 vivo 的支持

| 能力 | 状态 |
|---|---|
| 平台探测（`com.bbk.theme` + `ro.vivo.*` + 数据目录） | ✅ 已实现 |
| `.itz` 包体检（description.xml、顶层模块、自带字体告警） | ✅ 已实现，有夹具测试 |
| 交给商店导入 | ✅ `route_to_store.ps1`：推到 Download + 拉起 i主题，走「我的 → 主题 → 本地主题 → 导入」 |
| 直接投递 | ❌ 未实现（需私有 Binder + 真机反查） |

### 社区里的其它 vivo 路子（供参考）

- **vivo主题修改器 / 小千vivo主题助手**：把 `.itz` 验证/重打包后导入，导入后出现在
  「i主题 → 我的 → 主题 → 本地主题」，主题名会被改成固定名字（如「熊猫家族」）。
  注意要求文件放在**内部存储**，SD 卡/OTG 不行。
- **目录穿越注入**（B 站教程）：借文件管理器的路径穿越把 `.itz` 写进
  `/data/bbkcore/theme/.dwd/...`，再在商店里下载同名主题后替换。依赖特定文件管理器的漏洞，
  版本一变就失效，不建议依赖。

---

