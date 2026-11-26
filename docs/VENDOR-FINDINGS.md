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
- 该 build 里实现方法被混淆成短名（`n/p/s`(String)、`y`(String,Bitmap)、`onBind`…），
  说明接口方法名以 framework 里的 AIDL 为准，需 framework.jar 才能对齐
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

## 五、仍然没验证的部分

1. **MIUI 的 AIDL 方法名与参数** —— 需要 MIUI 的 `framework.jar`（`miui.content.res.IThemeService`）
   才能拿到真实签名；当前 build 里实现方法被混淆成 `n/p/s/y`。
2. **`miui.permission.USE_INTERNAL_GENERAL_API` 是否授予 shell(uid 2000)** ——
   ColorOS 的对应权限 shell 是有的（所以本项目能跑），MIUI 未知。
3. **真实 `.mtz` 的顶层目录清单** —— 手头没有真实 mtz 样本，模块名来自 dex 常量与公开资料。
4. **EMUI 的写入路径** —— `/data/themes/<id>/` 是公开资料说法，未在真机验证。

### 有真机后的验证顺序

```bash
# MIUI
adb shell pm list packages com.android.thememanager
adb shell dumpsys package com.android.thememanager | grep -A3 ThemeService
adb shell dumpsys package com.android.thememanager | grep USE_INTERNAL_GENERAL_API
adb shell ls -l /data/system/theme            # 需要 root
# 若权限给 shell：尝试投递
adb shell am startservice -n com.android.thememanager/com.android.thememanager.service.ThemeService \
  -a com.miui.service.THEMESERVICE

# EMUI
adb shell pm list packages | grep thememanager
adb shell ls -l /data/themes                  # 需要 root
```

拿到 `framework.jar` 后可以直接：

```powershell
aapt2 dump xmltree --file AndroidManifest.xml framework.jar
dexdump -d classes.dex | grep -A2 IThemeService
```
