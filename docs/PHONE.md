# 手机端方案（不 root 也能用）

两种身份任选其一，权限等价（都是 shell / root 级别）：

| 方式 | 前提 | 命令前缀 |
|---|---|---|
| **Shizuku 的 `rish`** | 装 Shizuku 并启动服务，开启「在终端应用中使用 Shizuku」 | `rish -c "..."` |
| root | KernelSU / Magisk 给 Termux 授权 | `su -c "..."` |
| adb | 电脑 `adb shell` | 直接执行 |

> 三者都会被系统视为 shell 身份，所以**都能投递 ThemeApplyService**，不需要真的 root。

---

## 一、准备

1. **Termux**（应用商店或 F-Droid 安装）
2. **Shizuku**（已安装 13.6.0）：
   - 打开 Shizuku → 启动服务（root 模式或无线调试）
   - 菜单里打开「**在终端应用中使用 Shizuku**」→ 会在
     `/sdcard/Android/data/moe.shizuku.privileged.api/` 生成 `rish` 等文件
3. 把 `theme.sh` 放到 `/sdcard/Download/theme.sh`
4. 需要设置锁屏壁纸时，先在电脑上构建并安装 LockWall：`.\tools\build-lockwall.ps1 -Install`

Termux 里执行一次，把 rish 加进 PATH：

```bash
mkdir -p ~/bin
cp /sdcard/Android/data/moe.shizuku.privileged.api/rish* ~/bin/ 2>/dev/null
chmod 700 ~/bin/rish
export PATH=$HOME/bin:$PATH          # 想长期生效可写进 ~/.bashrc
```

---

## 二、用法（推荐：装一次，之后一条命令）

### 一次性安装

```bash
sh /sdcard/Download/setup.sh
```

它会：装 `rish` 到 `~/bin`、生成 `theme` 命令、把 `~/bin` 加进 PATH、做自检。

### 之后只需要

```bash
theme
```

屏幕上会列出 `/sdcard/Download` 里的主题：

```
=== 可选主题（/sdcard/Download）===
  [1] 纳西妲ColorOS16主题.theme        64 MB
  [2] 别人给的.theme                  58 MB
  [0] 退出
  请输入序号: _
```

输个序号就自动跑完（应用 + 锁屏壁纸）。

### 也可以带参数

```bash
theme --status                        # 看当前主题
theme --lock-only n.theme             # 只设锁屏
theme n.theme --no-lock               # 只应用
```

### 没有 setup.sh 时的手动用法

```bash
rish -c "sh /sdcard/Download/theme.sh"                 # 菜单
rish -c "sh /sdcard/Download/theme.sh n.theme --no-lock"
```

---

## 三、免 root 的能力边界

| 能力 | 免 root（rish） | 有 root |
|---|---|---|
| 应用主题（壁纸/系统UI/设置/短信/联系人/图标/桌面） | ✅ | ✅ |
| 设置锁屏壁纸（lockwall） | ✅ | ✅ |
| 读取 `/data/theme` 模块清单 | ❌（SELinux 拒绝） | ✅ |
| **按内容补写缺失模块到 `/data/theme`** | ❌ | ✅ |
| 模块声明对齐 | 需要 `zip`（`pkg install zip`） | 可不改包，直接补写 |

意思就是：**免 root 能完整换主题**，只是"主题没声明 icons 时"这一种情况需要额外处理——
要么在 Termux 装 `zip` 让脚本自动对齐，要么在电脑上先对齐。

---

## 四、重复应用同一主题会"空转"

系统以 UUID 判断"是否已是当前主题"。UUID 相同就不会重做（没有反应）。

解决办法：**换一个 UUID**。

- 电脑端：`python tools\newuuid.py` 生成一个改过 UUID 的副本再应用；
- 手机端：换一个别的主题再换回来。

脚本也会提示：

```
[!]  当前已是该主题，系统不会重做（UUID 相同即视为已应用）
```

---

## 五、常见提示

| 提示 | 含义 |
|---|---|
| `[OK] 应用成功（UUID 已切换）` | 成功 |
| `[!] 当前已是该主题` | 见上一节，需换 UUID |
| `[!] 设备上没有 zip，跳过模块对齐` | 图标可能不生效，`pkg install zip` |
| `[!] 未安装 lockwall` | 锁屏这步被跳过（构建：`tools\build-lockwall.ps1 -Install`） |
| `[x] 投递服务失败` | 没拿到 shell/root 身份，检查 rish 或 su |