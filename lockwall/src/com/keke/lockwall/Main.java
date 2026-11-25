package com.keke.lockwall;

import android.app.Activity;
import android.app.WallpaperManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;

/**
 * 把指定图片设为锁屏壁纸（可选同时设桌面）。
 *
 * 为什么需要这个工具：
 *   ColorOS 的主题应用路径只调用 setDesktopWallpaper，主题包里的
 *   oppo_default_keyguard_wallpaper 不会被使用，所以锁屏壁纸需要单独设置。
 *
 * 用法:
 *   adb shell am start -n com.keke.lockwall/.Main --es path /sdcard/.../lock.jpg
 *   adb shell am start -n com.keke.lockwall/.Main --es path ... --ez desktop true
 *   不带 path 时使用内置的 assets/lock.jpg
 *
 * 注意：path 必须是本应用可读的文件。Android 11+ 上
 *       /data/local/tmp 与其它应用的外部私有目录都读不到，
 *       请放到本应用自己的 files 目录：
 *       /sdcard/Android/data/com.keke.lockwall/files/lock.jpg
 */
public class Main extends Activity {
    private static final String TAG = "LockWall";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        String path = getIntent() != null ? getIntent().getStringExtra("path") : null;
        boolean desktop = getIntent() != null && getIntent().getBooleanExtra("desktop", false);

        String source = "asset";
        Bitmap bmp = null;

        if (path != null && !path.isEmpty()) {
            File file = new File(path);
            if (file.exists() && file.canRead()) {
                try {
                    FileInputStream in = new FileInputStream(file);
                    try {
                        bmp = BitmapFactory.decodeStream(in);
                    } finally {
                        in.close();
                    }
                    source = "file:" + path;
                } catch (Throwable t) {
                    Log.e(TAG, "读取失败，改用内置图片: " + path, t);
                }
            } else {
                Log.w(TAG, "文件不可读，改用内置图片: " + path);
            }
        }

        if (bmp == null) {
            try {
                InputStream in = getAssets().open("lock.jpg");
                try {
                    bmp = BitmapFactory.decodeStream(in);
                } finally {
                    in.close();
                }
                source = "asset";
            } catch (Throwable t) {
                Log.e(TAG, "内置图片也读取失败", t);
            }
        }

        if (bmp == null) {
            finishWith("没有可用的图片");
            return;
        }

        Log.i(TAG, "source=" + source + " size=" + bmp.getWidth() + "x" + bmp.getHeight());

        try {
            WallpaperManager wm = WallpaperManager.getInstance(this);
            int which = WallpaperManager.FLAG_LOCK | (desktop ? WallpaperManager.FLAG_SYSTEM : 0);
            wm.setBitmap(bmp, null, true, which);
            Log.i(TAG, "setBitmap ok which=" + which + " from=" + source);
            String where = desktop ? "锁屏 + 桌面" : "锁屏";
            String suffix = source.startsWith("asset") ? "（内置图，非指定文件）" : "";
            toast("已设置" + where + "壁纸" + suffix);
        } catch (Throwable t) {
            Log.e(TAG, "setBitmap failed", t);
            finishWith("设置失败：" + t.getClass().getSimpleName());
            return;
        } finally {
            bmp.recycle();
        }
        finish();
    }

    private void finishWith(String message) {
        toast(message);
        finish();
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        Log.i(TAG, message);
    }
}
