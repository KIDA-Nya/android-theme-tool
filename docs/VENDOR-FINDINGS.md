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
