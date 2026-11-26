package com.keke.themetool;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.RemoteException;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * 这个 Service 由 Shizuku 以 shell 身份拉起（见 Shizuku.bindUserService），
 * 所以在这里执行 shell 命令 = 以 shell 身份执行。
 *
 * 注意：本类不能引用任何会崩的第三方类；只做"执行命令并回传输出"。
 */
public class ThemeRunnerService extends Service {

    private final IThemeRunner.Stub binder = new IThemeRunner.Stub() {
        @Override
        public String run(String script) throws RemoteException {
            return exec(script);
        }

        @Override
        public String whoami() throws RemoteException {
            return exec("id");
        }
    };

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    private String exec(String script) {
        StringBuilder sb = new StringBuilder();
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(new String[]{"sh", "-c", script});
            BufferedReader out = new BufferedReader(new InputStreamReader(p.getInputStream(), "UTF-8"));
            BufferedReader err = new BufferedReader(new InputStreamReader(p.getErrorStream(), "UTF-8"));
            String line;
            while ((line = out.readLine()) != null) {
                sb.append(line).append('\n');
            }
            while ((line = err.readLine()) != null) {
                sb.append(line).append('\n');
            }
            int code = p.waitFor();
            sb.append("[exit ").append(code).append("]\n");
        } catch (Exception e) {
            sb.append("[异常] ").append(e).append('\n');
        } finally {
            if (p != null) { try { p.destroy(); } catch (Exception ignored) { } }
        }
        return sb.toString();
    }
}
