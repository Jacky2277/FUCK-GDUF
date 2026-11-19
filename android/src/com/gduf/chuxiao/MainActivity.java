package com.gduf.chuxiao;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

public class MainActivity extends Activity {

    static final String UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 yiban_iOS/5.2.5(5104)";
    static final String BASE = "https://ygj.gduf.edu.cn";
    static final int GREEN = 0xFF78B842;

    SharedPreferences sp;
    final Handler ui = new Handler(Looper.getMainLooper());
    LinearLayout root;
    ScrollView scroll;

    // QR screen
    TextView titleView, nameView, countdownView, statusView;
    ImageView qrView;
    Button refreshBtn, overdueBtn, changeBtn, signBtn;
    TextView placeholder;
    volatile long endAt = 0;
    volatile boolean lastInbound = false;

    // setup screen
    EditText tokenInput;
    TextView setupHint;

    final Map<String, String> cookies = new HashMap<>();
    String studentID = "";
    String outSchoolID = "";
    String recType = "出";
    String lastName = "", lastStart = "", lastEnd = "";
    volatile boolean busy = false;
    volatile int gen = 0;
    volatile long nextRefreshAt = 0;

    static class Resp {
        int code;
        String body = "";
        String location = null;
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        sp = getSharedPreferences("cfg", 0);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(GREEN);
        scroll = new ScrollView(this);
        scroll.addView(root, new ViewGroup.LayoutParams(-1, -2));
        setContentView(scroll);
        if (token().isEmpty()) showSetup(false);
        else showQR(false);
    }

    String token() { return sp.getString("userToken", ""); }

    String uuid() {
        String u = sp.getString("deviceUuid", "");
        if (u.isEmpty()) {
            u = UUID.randomUUID().toString().toUpperCase(Locale.US);
            sp.edit().putString("deviceUuid", u).apply();
        }
        return u;
    }

    static String clean(String s) {
        return s == null ? "" : s.replaceAll("<[^>]+>", " ").replaceAll("\\s+", " ").trim();
    }

    int dp(float v) { return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()); }

    TextView tv(String s, float size, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(size);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setLineSpacing(dp(4), 1f);
        return t;
    }

    Button btn(String s, int bg) {
        Button b = new Button(this);
        b.setText(s);
        b.setTextSize(16);
        b.setTextColor(Color.WHITE);
        b.setBackgroundColor(bg);
        return b;
    }

    GradientDrawable bg(int color, float radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    Button pill(String s, int color, float radiusDp, float size) {
        Button b = new Button(this);
        b.setText(s);
        b.setTextSize(size);
        b.setTextColor(Color.WHITE);
        b.setAllCaps(false);
        b.setBackground(bg(color, radiusDp));
        return b;
    }

    void clearRoot() { root.removeAllViews(); }

    // ---------------- setup ----------------

    void showSetup(boolean expired) {
        gen++;
        clearRoot();
        LinearLayout pad = new LinearLayout(this);
        pad.setOrientation(LinearLayout.VERTICAL);
        pad.setPadding(dp(20), dp(36), dp(20), dp(30));
        root.addView(pad, new LinearLayout.LayoutParams(-1, -2));

        pad.addView(tv("出校码", 30, Color.WHITE, true));
        TextView sub = tv("首次使用需要填写一次易班 token", 14, 0xE6FFFFFF, false);
        sub.setPadding(0, dp(6), 0, dp(14));
        pad.addView(sub);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackgroundColor(Color.WHITE);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        pad.addView(card, new LinearLayout.LayoutParams(-1, -2));

        TextView step = tv(
                "1. 安装抓包工具（Stream / ProxyPin）\n" +
                "2. 打开易班 App → 易广金 → 出入申报 → 常规出入\n" +
                "3. 在抓包记录里找 f.yiban.cn 的请求\n" +
                "4. 复制请求头里的 loginToken（32 位）\n" +
                "5. 粘贴到下面，点“开始使用”", 13, 0xFF333333, false);
        card.addView(step);

        tokenInput = new EditText(this);
        tokenInput.setHint("粘贴 32 位 user token");
        tokenInput.setTextSize(13);
        tokenInput.setSingleLine(true);
        tokenInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD);
        tokenInput.setTypeface(Typeface.MONOSPACE);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, dp(46));
        lp.topMargin = dp(12);
        card.addView(tokenInput, lp);

        Button go = btn("开始使用", 0xFF1B8C33);
        LinearLayout.LayoutParams glp = new LinearLayout.LayoutParams(-1, dp(46));
        glp.topMargin = dp(10);
        card.addView(go, glp);
        go.setOnClickListener(v -> saveToken());

        Button det = new Button(this);
        det.setText("详细教程");
        det.setTextSize(14);
        det.setBackgroundColor(Color.TRANSPARENT);
        det.setTextColor(0xFF1B8C33);
        card.addView(det);
        det.setOnClickListener(v -> showDetail());

        setupHint = tv(expired ? "token 已失效，请重新抓一次并粘贴" : "token 只保存在本机，不会上传", 12,
                expired ? 0xFFCC0000 : 0xFF777777, false);
        setupHint.setPadding(dp(2), dp(8), dp(2), 0);
        card.addView(setupHint);

        if (!token().isEmpty()) {
            Button back = new Button(this);
            back.setText("返回");
            back.setTextSize(14);
            back.setBackgroundColor(Color.TRANSPARENT);
            back.setTextColor(Color.WHITE);
            back.setOnClickListener(v -> showQR(false));
            pad.addView(back);
        }
    }

    void showDetail() {
        String msg = "1. 安装 ProxyPin（应用商店搜索，或官网下载 apk）\n" +
                "2. 打开 ProxyPin，点「开始抓包」；首次使用按提示安装 CA 证书（设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书）\n" +
                "3. 保持抓包，打开易班 App → 易广金 → 出入申报 → 常规出入，停在二维码页\n" +
                "4. 回 ProxyPin 停止抓包，找到 f.yiban.cn 的请求（地址里带 iapp378946 或 iapp/index）\n" +
                "5. 点开请求 → 请求头 → 找到 Cookie，复制 loginToken= 后面那 32 位字符（到分号为止，不要带空格）\n" +
                "6. 粘贴到输入框，点「开始使用」\n\n" +
                "token 只保存在本机，不会上传；失效时 App 会提示重新抓取。\n" +
                "抓不到 f.yiban.cn：确认停在二维码页，清空记录后重抓一次。";
        new AlertDialog.Builder(this).setTitle("详细教程").setMessage(msg)
                .setPositiveButton("知道了", null).show();
    }

    void saveToken() {
        String t = tokenInput.getText().toString().trim();
        if (t.length() < 32) {
            setupHint.setText("token 应该是 32 位十六进制字符，检查一下是否复制完整");
            return;
        }
        sp.edit().putString("userToken", t).apply();
        showQR(false);
    }

    // ---------------- QR screen ----------------

    void showQR(boolean auto) {
        gen++;
        clearRoot();
        LinearLayout pad = new LinearLayout(this);
        pad.setOrientation(LinearLayout.VERTICAL);
        pad.setGravity(Gravity.CENTER_HORIZONTAL);
        pad.setPadding(dp(20), dp(46), dp(20), dp(30));
        root.addView(pad, new LinearLayout.LayoutParams(-1, -2));

        titleView = tv("出校凭证", 30, Color.WHITE, true);
        titleView.setGravity(Gravity.CENTER);
        pad.addView(titleView);

        nameView = tv("正在加载…", 14, 0xE6FFFFFF, false);
        nameView.setGravity(Gravity.CENTER);
        nameView.setPadding(dp(6), dp(8), dp(6), dp(18));
        pad.addView(nameView);

        int side = Math.min(getResources().getDisplayMetrics().widthPixels - dp(72), dp(300));
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(bg(Color.WHITE, 18));
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(side + dp(28), side + dp(28));
        pad.addView(card, clp);

        qrView = new ImageView(this);
        card.addView(qrView, new LinearLayout.LayoutParams(side, side));

        placeholder = tv("点击下方按钮\n生成凭证", 16, 0xFF9AA0A6, false);
        placeholder.setGravity(Gravity.CENTER);
        placeholder.setVisibility(View.GONE);
        card.addView(placeholder, new LinearLayout.LayoutParams(side, side));

        countdownView = tv("", 15, Color.WHITE, true);
        countdownView.setGravity(Gravity.CENTER);
        countdownView.setPadding(0, dp(16), 0, 0);
        pad.addView(countdownView);

        statusView = tv("正在生成…", 12, 0xBFFFFFFF, false);
        statusView.setGravity(Gravity.CENTER);
        statusView.setPadding(dp(10), dp(6), dp(10), 0);
        pad.addView(statusView);

        refreshBtn = pill("刷新凭证", 0x2EFFFFFF, 22, 17);
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(dp(210), dp(46));
        rlp.topMargin = dp(18);
        pad.addView(refreshBtn, rlp);
        refreshBtn.setOnClickListener(v -> refresh());

        overdueBtn = pill("跨天返校（出校超时）", 0x1FFFFFFF, 22, 14);
        LinearLayout.LayoutParams olp = new LinearLayout.LayoutParams(dp(210), dp(42));
        olp.topMargin = dp(10);
        pad.addView(overdueBtn, olp);
        overdueBtn.setOnClickListener(v -> doOverdue());

        signBtn = pill("签到考勤", 0x33FFFFFF, 22, 15);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(dp(210), dp(44));
        slp.topMargin = dp(10);
        pad.addView(signBtn, slp);
        signBtn.setOnClickListener(v -> startActivity(new Intent(this, SignActivity.class)));

        changeBtn = new Button(this);
        changeBtn.setText("更换 token");
        changeBtn.setTextSize(12);
        changeBtn.setAllCaps(false);
        changeBtn.setBackgroundColor(Color.TRANSPARENT);
        changeBtn.setTextColor(0xF2FFFFFF);
        LinearLayout.LayoutParams chlp = new LinearLayout.LayoutParams(-2, -2);
        chlp.topMargin = dp(8);
        pad.addView(changeBtn, chlp);
        changeBtn.setOnClickListener(v -> confirmChangeToken());

        if (auto) {
            qrView.setVisibility(View.VISIBLE);
            placeholder.setVisibility(View.GONE);
            refresh();
        } else {
            qrView.setVisibility(View.GONE);
            placeholder.setVisibility(View.VISIBLE);
            nameView.setText("还没有生成凭证");
            statusView.setText("点下方按钮，才会向学校提交一条常规出入申请");
            refreshBtn.setText("生成凭证");
        }
    }

    void confirmChangeToken() {
        new AlertDialog.Builder(this)
                .setMessage("更换 token 会回到填写页，已保存的 token 不会丢。")
                .setNegativeButton("取消", null)
                .setPositiveButton("更换", (d, w) -> showSetup(false))
                .show();
    }

    // ---------------- network ----------------

    String cookieHeader() {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : cookies.entrySet()) {
            if (sb.length() > 0) sb.append("; ");
            sb.append(e.getKey()).append('=').append(e.getValue());
        }
        return sb.toString();
    }

    void captureCookies(HttpURLConnection c) {
        Map<String, List<String>> hf = c.getHeaderFields();
        for (Map.Entry<String, List<String>> e : hf.entrySet()) {
            if (e.getKey() == null || !"set-cookie".equalsIgnoreCase(e.getKey())) continue;
            for (String line : e.getValue()) {
                if (line == null) continue;
                String kv = line.split(";", 2)[0];
                int i = kv.indexOf('=');
                if (i > 0) cookies.put(kv.substring(0, i).trim(), kv.substring(i + 1).trim());
            }
        }
    }

    static String read(InputStream is) throws Exception {
        if (is == null) return "";
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = is.read(buf)) > 0) bos.write(buf, 0, n);
        is.close();
        return new String(bos.toByteArray(), StandardCharsets.UTF_8);
    }

    Resp req(String method, String url, String body, Map<String, String> extra) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(15000);
        c.setReadTimeout(20000);
        c.setRequestMethod(method);
        c.setRequestProperty("User-Agent", UA);
        c.setRequestProperty("Accept", "text/html,application/json,application/xhtml+xml,*/*");
        c.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        String cookie = (extra != null && extra.containsKey("Cookie")) ? extra.get("Cookie") : cookieHeader();
        if (cookie != null && !cookie.isEmpty()) c.setRequestProperty("Cookie", cookie);
        if (extra != null) {
            for (Map.Entry<String, String> e : extra.entrySet()) {
                if (!"Cookie".equals(e.getKey()) && e.getValue() != null) c.setRequestProperty(e.getKey(), e.getValue());
            }
        }
        if (body != null) {
            c.setDoOutput(true);
            byte[] bb = body.getBytes(StandardCharsets.UTF_8);
            c.setFixedLengthStreamingMode(bb.length);
            if (c.getRequestProperty("Content-Type") == null)
                c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
            OutputStream os = c.getOutputStream();
            os.write(bb);
            os.close();
        }
        Resp r = new Resp();
        r.code = c.getResponseCode();
        captureCookies(c);
        r.location = c.getHeaderField("Location");
        try {
            r.body = read(r.code >= 400 ? c.getErrorStream() : c.getInputStream());
        } catch (Exception ignored) { }
        c.disconnect();
        return r;
    }

    static String form(Map<String, String> m) throws Exception {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : m.entrySet()) {
            if (sb.length() > 0) sb.append('&');
            sb.append(URLEncoder.encode(e.getKey(), "UTF-8")).append('=').append(URLEncoder.encode(e.getValue() == null ? "" : e.getValue(), "UTF-8"));
        }
        return sb.toString();
    }

    static String param(String url, String key) {
        try {
            int q = url.indexOf('?');
            if (q < 0) return null;
            for (String kv : url.substring(q + 1).split("&")) {
                int i = kv.indexOf('=');
                if (i > 0 && URLEncoder.encode(key, "UTF-8").equals(kv.substring(0, i)))
                    return java.net.URLDecoder.decode(kv.substring(i + 1), "UTF-8");
            }
        } catch (Exception ignored) { }
        return null;
    }

    String fetchVerify(String tok) throws Exception {
        Map<String, String> h = new HashMap<>();
        h.put("Authorization", "Bearer " + tok);
        h.put("loginToken", tok);
        h.put("AppVersion", "5.2.5");
        h.put("Cookie", "client=iOS; loginToken=" + tok + "; yiban_user_token=" + tok);
        h.put("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        Resp r = req("GET", "https://f.yiban.cn/iapp378946", null, h);
        String loc = r.location;
        if (loc != null && loc.contains("verify_request=")) return param(loc, "verify_request");
        if (loc != null && (loc.contains("act=iapp378946") || loc.contains("/iapp/index"))) {
            if (loc.startsWith("/")) loc = "https://f.yiban.cn" + loc;
            else if (!loc.startsWith("http")) loc = "https://f.yiban.cn/" + loc;
            Resp r2 = req("GET", loc, null, h);
            if (r2.location != null && r2.location.contains("verify_request=")) return param(r2.location, "verify_request");
        }
        return null;
    }

    static String multipartLogin(String verify) {
        String b = "----GDUFBoundary" + System.currentTimeMillis();
        StringBuilder sb = new StringBuilder();
        sb.append("--").append(b).append("\r\nContent-Disposition: form-data; name=\"loginToken\"\r\n\r\n\r\n");
        sb.append("--").append(b).append("\r\nContent-Disposition: form-data; name=\"verify_request\"\r\n\r\n").append(verify).append("\r\n");
        sb.append("--").append(b).append("--\r\n");
        return sb.toString();
    }

    Map<String, String> gh;

    static class QRResult {
        String qr = "", name = "", start = "", end = "", type = "出", oid = "";
    }

    String prepareSession() throws Exception {
        cookies.clear();
        final String tok = token();
        if (tok.isEmpty()) throw new Exception("TOKEN_EMPTY");

        String verify = fetchVerify(tok);
        if (verify == null || verify.isEmpty()) throw new Exception("TOKEN_EXPIRED");

        String b = "----GDUFBoundary" + System.currentTimeMillis();
        String body = "--" + b + "\r\nContent-Disposition: form-data; name=\"loginToken\"\r\n\r\n\r\n"
                + "--" + b + "\r\nContent-Disposition: form-data; name=\"verify_request\"\r\n\r\n" + verify + "\r\n"
                + "--" + b + "--\r\n";
        Map<String, String> lh = new HashMap<>();
        lh.put("Content-Type", "multipart/form-data; boundary=" + b);
        lh.put("X-Requested-With", "XMLHttpRequest");
        lh.put("Cookie", "client=iOS");
        Resp lr = req("POST", BASE + "/Handler/login.ashx?flag=login", body, lh);
        JSONObject lj = new JSONObject(lr.body);
        if (lj.optInt("code") != 0) throw new Exception("ygj 登录失败：" + clean(lj.optString("msg")));
        String goTo = lj.optString("goToUrl", "");
        int si = goTo.indexOf("studentID=");
        String sid = si >= 0 ? goTo.substring(si + 10).split("[^0-9]")[0] : "";
        studentID = sid;
        cookies.put("client", "iOS");
        if (!sid.isEmpty()) cookies.put("studentID", sid);

        gh = new HashMap<>();
        gh.put("X-Requested-With", "XMLHttpRequest");
        gh.put("Referer", BASE + "/ygj2024/student-default.aspx?studentID=" + sid);
        req("GET", BASE + goTo, null, gh);

        req("POST", BASE + "/Handler/device.ashx?flag=getNotice", form(mapOf("studentID", sid)), gh);

        String duuid = uuid();
        String dmodel = android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL;
        String dsys = android.os.Build.VERSION.RELEASE;
        String dapp = "5.2.5";
        try {
            Resp sr = req("POST", BASE + "/Handler/device.ashx?flag=getStudentDevice",
                    form(mapOf("studentID", sid)), gh);
            JSONArray sa = new JSONObject(sr.body).optJSONArray("data");
            if (sa != null) for (int i = 0; i < sa.length(); i++) {
                JSONObject o = sa.getJSONObject(i);
                if ("1".equals(o.optString("state"))) {
                    duuid = o.optString("uuid", duuid);
                    dmodel = o.optString("deviceModel", dmodel);
                    dsys = o.optString("systemVersion", dsys);
                    dapp = o.optString("appVersion", dapp);
                    break;
                }
            }
        } catch (Exception ignored) {
        }

        JSONObject dev = new JSONObject();
        dev.put("uuid", duuid);
        dev.put("appVersion", dapp);
        dev.put("deviceModel", dmodel);
        dev.put("systemVersion", dsys);
        Resp dr = req("POST", BASE + "/Handler/device.ashx?flag=checkBindDevice",
                form(mapOf("deviceData", dev.toString(), "autoBind", "false")), gh);
        JSONObject dj = new JSONObject(dr.body);
        if (dj.optInt("code") == 1) {
            dev.put("uuid", uuid());
            dev.put("deviceModel", android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL);
            dev.put("systemVersion", android.os.Build.VERSION.RELEASE);
            Resp dr2 = req("POST", BASE + "/Handler/device.ashx?flag=checkBindDevice",
                    form(mapOf("deviceData", dev.toString(), "autoBind", "true")), gh);
            JSONObject dj2 = new JSONObject(dr2.body);
            if (dj2.optInt("code") != 0) throw new Exception("设备绑定失败：" + clean(dj2.optString("msg")));
        } else if (dj.optInt("code") != 0) {
            throw new Exception("设备校验失败：" + clean(dj.optString("msg")));
        }
        return sid;
    }

    String findLatestRecord(String sid, String type) {
        try {
            Resp mr = req("POST", BASE + "/Handler/outschool.ashx?flag=getMyOutSchool",
                    form(mapOf("studentID", sid)), gh);
            JSONArray arr = new JSONObject(mr.body).optJSONArray("data");
            if (arr != null) for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                if (type.equals(o.optString("type", ""))) return o.optString("outSchoolID", "");
            }
        } catch (Exception ignored) {
        }
        return "";
    }

    QRResult loadQRForRecord(String sid, String oid, String type) throws Exception {
        QRResult q = new QRResult();
        q.oid = oid;
        q.type = type;
        String page = BASE + "/ygj2024/outschool/student-outschool.aspx?type="
                + URLEncoder.encode(type, "UTF-8") + "&outSchoolID=" + oid;
        Map<String, String> h = new HashMap<>(gh);
        h.put("Referer", page);
        req("GET", page, null, h);

        Resp pr = req("POST", BASE + "/Handler/outschool.ashx?flag=getPassRecord",
                form(mapOf("studentID", sid, "outSchoolID", oid, "type", type)), h);
        JSONObject pj = new JSONObject(pr.body);
        if (pj.optInt("code") != 0) throw new Exception("读取凭证失败：" + clean(pj.optString("msg")));
        JSONArray arr = pj.optJSONArray("data");
        if (arr == null || arr.length() == 0) throw new Exception("凭证不存在或已过期");
        JSONObject o = arr.getJSONObject(0);
        q.name = o.optString("studentName", o.optString("name", ""));
        q.start = o.optString("startTime", o.optString("startDate", ""));
        q.end = o.optString("endTime", o.optString("endDate", ""));

        Resp qr = req("POST", BASE + "/Handler/outschool.ashx?flag=getQrcode",
                form(mapOf("outSchoolID", oid)), h);
        JSONObject qj = new JSONObject(qr.body);
        if (qj.optInt("code") != 0) throw new Exception("取二维码失败：" + clean(qj.optString("msg")));
        q.qr = qj.optString("qrcode", "");
        if (q.qr.isEmpty()) throw new Exception("二维码为空");
        return q;
    }

    void finishQR(QRResult q, int my) throws Exception {
        final Bitmap bmp = makeQR(q.qr + (System.currentTimeMillis() / 1000L), 720);
        if (!q.name.isEmpty()) lastName = q.name;
        if (!q.start.isEmpty()) lastStart = q.start;
        if (!q.end.isEmpty()) lastEnd = q.end;
        final boolean inbound = "入".equals(q.type);
        final String nm = lastName;
        final String st = lastStart;
        final String tt = timeNow();
        final long endMs = parseTime(lastEnd);
        ui.post(() -> {
            if (my != gen || qrView == null) return;
            titleView.setText(inbound ? "入校凭证" : "出校凭证");
            String who = nm.isEmpty() ? "" : (nm + (studentID.isEmpty() ? "" : "（" + studentID + "）"));
            nameView.setText(who.isEmpty() ? "" : (who + "同学可于 " + dayOf(st) + (inbound ? " 入校" : " 出校")));
            qrView.setVisibility(View.VISIBLE);
            if (placeholder != null) placeholder.setVisibility(View.GONE);
            if (refreshBtn != null) refreshBtn.setText("刷新凭证");
            qrView.setImageBitmap(bmp);
            endAt = endMs;
            lastInbound = inbound;
            statusView.setText("凭证 " + tt + " 生成，每 60 秒自动刷新");
            nextRefreshAt = System.currentTimeMillis() + 60000;
            scheduleTick(my);
        });
    }

    void doRefresh(final int my) throws Exception {
        String sid = prepareSession();
        Resp ar = req("POST", BASE + "/Handler/outschool.ashx?flag=autoCreateOutSchoolRecord",
                form(mapOf("studentID", sid)), gh);
        JSONObject aj = new JSONObject(ar.body);
        if (aj.optInt("code") != 0) throw new Exception("生成凭证失败：" + clean(aj.optString("msg")));
        String oid = aj.optString("outSchoolID", "");
        String type = aj.optString("type", "出");
        if (type.isEmpty()) type = "出";
        if (oid.isEmpty()) oid = findLatestRecord(sid, type);
        if (oid.isEmpty()) throw new Exception("没有拿到凭证号，请稍后重试");
        outSchoolID = oid;
        recType = type;
        finishQR(loadQRForRecord(sid, oid, type), my);
    }

    void doOverdue() {
        new AlertDialog.Builder(this)
                .setTitle("跨天返校")
                .setMessage("将向学校提交一条「出校超时（申请进校）」：\n去向：广东省广州市天河区\n日期：今天\n次数：共一次出入\n\n提交后会生成入校凭证。")
                .setNegativeButton("取消", null)
                .setPositiveButton("提交并生成入校码", (d, w) -> runOverdue())
                .show();
    }

    void runOverdue() {
        if (busy) return;
        busy = true;
        final int my = ++gen;
        if (statusView != null) statusView.setText("正在提交出校超时（申请进校）…");
        new Thread(() -> {
            try {
                finishQR(applyOverdueReturn(prepareSession()), my);
            } catch (final Exception e) {
                ui.post(() -> {
                    if (statusView != null && my == gen) statusView.setText("出错：" + e.getMessage());
                });
            } finally {
                busy = false;
            }
        }).start();
    }

    QRResult applyOverdueReturn(String sid) throws Exception {
        String today = new java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new java.util.Date());
        String addPage = BASE + "/ygj2024/outschool/student-add.aspx";
        Map<String, String> h = new HashMap<>(gh);
        h.put("Referer", addPage);
        req("GET", addPage, null, h);
        Map<String, String> f = mapOf(
                "outSchoolID", "0", "studentID", sid, "days", "1", "passNum", "共一次出入",
                "outType", "CXCS", "outTypeName", "出校超时（申请进校）",
                "outAddress", "广东省广州市天河区", "startDate", today, "endDate", today,
                "linkName", "", "linkPhone", "", "phone", "", "images", "", "picture1", "", "picture2", "");
        Resp sr = req("POST", BASE + "/Handler/outschool.ashx?flag=save", form(f), h);
        JSONObject sj = new JSONObject(sr.body);
        if (sj.optInt("code") != 0) throw new Exception("提交失败：" + clean(sj.optString("msg")));
        String oid = sj.optString("outSchoolID", "");
        if (oid.isEmpty() || "0".equals(oid)) {
            Resp mr = req("POST", BASE + "/Handler/outschool.ashx?flag=getMyOutSchool",
                    form(mapOf("studentID", sid)), h);
            JSONArray arr = new JSONObject(mr.body).optJSONArray("data");
            if (arr != null) for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                if (o.optString("outTypeName", "").contains("超时") || "入".equals(o.optString("type"))) {
                    oid = o.optString("outSchoolID", "");
                    break;
                }
            }
        }
        if (oid.isEmpty()) throw new Exception("提交成功，但没找到入校凭证，请点刷新重试");
        outSchoolID = oid;
        recType = "入";
        return loadQRForRecord(sid, oid, "入");
    }

    static long parseTime(String s) {
        if (s == null) return 0;
        try {
            String t = s.trim().replace('/', '-');
            if (t.length() >= 19) t = t.substring(0, 19);
            return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).parse(t).getTime();
        } catch (Exception e) {
            return 0;
        }
    }

    static String dayOf(String s) {
        if (s == null) return "";
        String t = s.trim().replace('/', '-');
        return t.length() >= 10 ? t.substring(0, 10) : t;
    }

    static String timeNow() {
        return new java.text.SimpleDateFormat("HH:mm:ss", Locale.US).format(new java.util.Date());
    }

    void scheduleTick(final int my) {
        ui.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (countdownView == null || my != gen) return;
                long now = System.currentTimeMillis();
                if (now >= nextRefreshAt) { refresh(); return; }
                if (endAt > 0) {
                    long left = (endAt - now) / 1000;
                    if (left <= 0) {
                        countdownView.setText("该凭证已失效，正在重新生成…");
                        refresh();
                        return;
                    }
                    countdownView.setText(String.format(Locale.US, "该凭证 %02d:%02d 后将失效，请尽快%s校",
                            left / 60, left % 60, lastInbound ? "入" : "出"));
                }
                ui.postDelayed(this, 1000);
            }
        }, 1000);
    }

    void refresh() {
        if (busy) return;
        busy = true;
        final int my = ++gen;
        if (statusView != null) statusView.setText("正在生成…");
        new Thread(() -> {
            try {
                doRefresh(my);
            } catch (final Exception e) {
                final String msg = e.getMessage() == null ? "" : e.getMessage();
                ui.post(() -> {
                    if (my != gen) return;
                    if ("TOKEN_EMPTY".equals(msg)) { showSetup(false); return; }
                    if ("TOKEN_EXPIRED".equals(msg)) { showSetup(true); return; }
                    if (statusView != null) statusView.setText("出错：" + msg);
                });
            } finally {
                busy = false;
            }
        }).start();
    }

    static Map<String, String> mapOf(String... kv) {
        Map<String, String> m = new HashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put(kv[i], kv[i + 1]);
        return m;
    }

    Bitmap makeQR(String text, int size) throws Exception {
        Map<EncodeHintType, Object> hints = new HashMap<>();
        hints.put(EncodeHintType.CHARACTER_SET, "UTF-8");
        hints.put(EncodeHintType.MARGIN, 1);
        BitMatrix m = new QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints);
        Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                bmp.setPixel(x, y, m.get(x, y) ? Color.BLACK : Color.WHITE);
        return bmp;
    }
}
