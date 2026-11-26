package com.keke.themetool;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import rikka.shizuku.Shizuku;

public class MainActivity extends Activity {

    private static final String[] EXT = {".theme", ".mtz", ".hwt", ".hnt", ".itz"};

    private TextView statusView;
    private TextView logView;
    private ListView listView;
    private final List<File> themes = new ArrayList<>();

    private String platform = "unknown";
    private String storePkg = "";
    private IThemeRunner runner;          // Shizuku 用户服务
    private boolean shizukuReady = false;

    private final Handler ui = new Handler(Looper.getMainLooper());

    private final ServiceConnection conn = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            runner = IThemeRunner.Stub.asInterface(service);
            shizukuReady = true;
            log("已连上 Shizuku 用户服务");
            try { log("身份：" + runner.whoami().trim()); } catch (Exception e) { log("whoami 失败: " + e); }
            refresh();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            runner = null;
            shizukuReady = false;
            log("Shizuku 用户服务断开");
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (12 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        statusView = new TextView(this);
        statusView.setTextSize(14);
        root.addView(statusView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        Button refreshBtn = new Button(this);
        refreshBtn.setText("刷新");
        refreshBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { refresh(); }
        });
        Button shizukuBtn = new Button(this);
        shizukuBtn.setText("连接 Shizuku");
        shizukuBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { connectShizuku(); }
        });
        bar.addView(refreshBtn);
        bar.addView(shizukuBtn);
        root.addView(bar);

        listView = new ListView(this);
        root.addView(listView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        ScrollView scroll = new ScrollView(this);
        logView = new TextView(this);
        logView.setTextSize(11);
        logView.setPadding(0, pad, 0, 0);
        scroll.addView(logView);
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);

        detectPlatform();

        Shizuku.addBinderReceivedListenerSticky(new Shizuku.OnBinderReceivedListener() {
            public void onBinderReceived() { ui.post(new Runnable() { public void run() { log("Shizuku 服务已就绪"); } }); }
        });

        refresh();
        tryConnectIfPermitted();
    }

    // ---------------------------------------------------------------- 平台识别

    private void detectPlatform() {
        if (installed("com.heytap.themestore")) { platform = "coloros"; storePkg = "com.heytap.themestore"; }
        else if (installed("com.oplus.themestore")) { platform = "coloros"; storePkg = "com.oplus.themestore"; }
        else if (installed("com.android.thememanager")) { platform = "miui"; storePkg = "com.android.thememanager"; }
        else if (installed("com.hihonor.android.thememanager")) { platform = "honor"; storePkg = "com.hihonor.android.thememanager"; }
        else if (installed("com.huawei.android.thememanager")) { platform = "huawei"; storePkg = "com.huawei.android.thememanager"; }
        else if (installed("com.bbk.theme")) { platform = "vivo"; storePkg = "com.bbk.theme"; }

        String label;
        switch (platform) {
            case "coloros": label = "ColorOS（OPPO / 一加 / realme）→ 可直接应用"; break;
            case "miui":    label = "MIUI / HyperOS（小米）→ 交给商店导入"; break;
            case "huawei":  label = "EMUI / HarmonyOS（华为）→ 放到 Huawei/Themes"; break;
            case "honor":   label = "MagicOS（荣耀）→ 放到荣耀主题目录"; break;
            case "vivo":    label = "OriginOS（vivo / iQOO）→ 交给 i主题 导入"; break;
            default:        label = "未识别的平台";
        }
        statusView.setText("平台：" + label + "\n主题商店：" + (storePkg.isEmpty() ? "无" : storePkg));
        log("平台识别：" + platform + " / " + storePkg);
    }

    private boolean installed(String pkg) {
        try {
            getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    // ---------------------------------------------------------------- 主题列表

    private void refresh() {
        themes.clear();
        for (String dir : new String[]{"/sdcard/Download", "/sdcard"}) {
            File d = new File(dir);
            File[] fs = d.listFiles();
            if (fs == null) continue;
            for (File f : fs) {
                if (!f.isFile()) continue;
                String n = f.getName().toLowerCase();
                for (String e : EXT) {
                    if (n.endsWith(e)) { themes.add(f); break; }
                }
            }
        }
        Collections.sort(themes);

        List<String> names = new ArrayList<>();
        for (File f : themes) names.add(f.getName() + "    (" + (f.length() / 1024 / 1024) + " MB)");

        ArrayAdapter<String> ad = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, names);
        listView.setAdapter(ad);
        listView.setOnItemClickListener((parent, view, position, id) -> confirm(themes.get(position)));

        log("找到 " + themes.size() + " 个主题包（/sdcard/Download 与 /sdcard）");
        if (themes.isEmpty()) log("把主题包放到 /sdcard/Download 后点「刷新」");
    }

    private void confirm(final File theme) {
        String action;
        switch (platform) {
            case "coloros": action = "直接应用到系统（需要 Shizuku 或 root）"; break;
            default: action = "推送到主题商店并打开它（本平台不支持直接应用）"; break;
        }
        new AlertDialog.Builder(this)
                .setTitle(theme.getName())
                .setMessage(action)
                .setPositiveButton("执行", (d, w) -> doApply(theme))
                .setNegativeButton("取消", null)
                .show();
    }

    // ---------------------------------------------------------------- 执行

    private void doApply(final File theme) {
        final String path = theme.getAbsolutePath();
        new Thread(() -> {
            String script = buildScript(platform, path);
            log("\n$ " + script.replace("\n", "\n$ "));
            String out;
            if (shizukuReady && runner != null) {
                try { out = runner.run(script); }
                catch (Exception e) { out = "[Shizuku 执行失败] " + e + "\n" + rootRun(script); }
            } else {
                out = rootRun(script);
            }
            log(out);
            if ("coloros".equals(platform)) {
                log("校验：");
                log(runQuiet("settings get global applied_default_theme_package_name"));
            } else {
                log("接下来在手机上按提示点几下完成导入。");
            }
        }).start();
    }

    private String rootRun(String script) {
        StringBuilder sb = new StringBuilder("[未连上 Shizuku，改用 root]\n");
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(new String[]{"su", "-c", script});
            BufferedReader o = new BufferedReader(new InputStreamReader(p.getInputStream(), "UTF-8"));
            BufferedReader e = new BufferedReader(new InputStreamReader(p.getErrorStream(), "UTF-8"));
            String l;
            while ((l = o.readLine()) != null) sb.append(l).append('\n');
            while ((l = e.readLine()) != null) sb.append(l).append('\n');
            sb.append("[exit ").append(p.waitFor()).append("]\n");
        } catch (Exception ex) {
            sb.append("[root 不可用] ").append(ex).append('\n')
              .append("请点「连接 Shizuku」并授权，或在 root 管理器里给本应用授权。\n");
        } finally {
            if (p != null) { try { p.destroy(); } catch (Exception ignored) { } }
        }
        return sb.toString();
    }

    private String runQuiet(String cmd) {
        if (shizukuReady && runner != null) {
            try { return runner.run(cmd); } catch (Exception ignored) { }
        }
        return rootRun(cmd);
    }

    private String buildScript(String platform, String path) {
        StringBuilder sb = new StringBuilder();
        switch (platform) {
            case "coloros":
                sb.append("appops set ").append(storePkg).append(" MANAGE_EXTERNAL_STORAGE allow\n");
                sb.append("am force-stop ").append(storePkg).append("\n");
                sb.append("input keyevent KEYCODE_WAKEUP\n");
                sb.append("am startservice -n ").append(storePkg)
                  .append("/com.nearme.themespace.services.ThemeApplyService")
                  .append(" --es THEME_PATH '").append(path).append("'\n");
                break;
            case "miui":
                sb.append("cp -f '").append(path).append("' /sdcard/Download/\n");
                sb.append("monkey -p ").append(storePkg)
                  .append(" -c android.intent.category.LAUNCHER 1\n");
                break;
            case "honor":
                sb.append("mkdir -p /sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes\n");
                sb.append("cp -f '").append(path)
                  .append("' /sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes/\n");
                sb.append("monkey -p ").append(storePkg)
                  .append(" -c android.intent.category.LAUNCHER 1\n");
                break;
            case "huawei":
                sb.append("mkdir -p /sdcard/Huawei/Themes\n");
                sb.append("cp -f '").append(path).append("' /sdcard/Huawei/Themes/\n");
                sb.append("monkey -p ").append(storePkg)
                  .append(" -c android.intent.category.LAUNCHER 1\n");
                break;
            case "vivo":
                sb.append("cp -f '").append(path).append("' /sdcard/Download/\n");
                sb.append("monkey -p ").append(storePkg)
                  .append(" -c android.intent.category.LAUNCHER 1\n");
                break;
            default:
                sb.append("echo 'unsupported platform'\n");
        }
        return sb.toString();
    }

    // ---------------------------------------------------------------- Shizuku

    private void connectShizuku() {
        if (!Shizuku.pingBinder()) {
            log("Shizuku 服务没在跑：请先启动 Shizuku（可用 root 或无线调试启动）");
            return;
        }
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            log("请求 Shizuku 授权…");
            Shizuku.requestPermission(0);
            Shizuku.addRequestPermissionResultListener(new Shizuku.OnRequestPermissionResultListener() {
                public void onRequestPermissionResult(int requestCode, int grantResult) {
                    if (grantResult == PackageManager.PERMISSION_GRANTED) {
                        ui.post(() -> { log("已授权，开始绑定用户服务"); bindService0(); });
                    } else {
                        ui.post(() -> log("Shizuku 授权被拒绝"));
                    }
                }
            });
            return;
        }
        bindService0();
    }

    private void tryConnectIfPermitted() {
        try {
            if (Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                bindService0();
            }
        } catch (Throwable ignored) { }
    }

    private void bindService0() {
        try {
            Shizuku.UserServiceArgs args = new Shizuku.UserServiceArgs(
                    new ComponentName(getPackageName(), ThemeRunnerService.class.getName()))
                    .processNameSuffix("runner")
                    .debuggable(false)
                    .version(1);
            Shizuku.bindUserService(args, conn);
            log("正在绑定 Shizuku 用户服务…");
        } catch (Throwable t) {
            log("绑定失败：" + t);
        }
    }

    // ---------------------------------------------------------------- 工具

    private void log(final String s) {
        ui.post(() -> logView.append(s.endsWith("\n") ? s : s + "\n"));
    }
}
