package com.gduf.chuxiao;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

/** 签到考勤：原生接口取课表/当前课程，扫码后直接提交，不依赖网页 JS。 */
public class SignActivity extends Activity {

    static final int REQ_SCAN = 11;
    static final int REQ_TEST = 12;
    static final int GREEN = 0xFF78B842;
    static final int BAR = 0xFF6CA53A;

    final Handler ui = new Handler(Looper.getMainLooper());
    SharedPreferences sp;
    YgjClient client;
    String sid = "";
    JSONArray schedule = new JSONArray();

    boolean loading = false;
    boolean hasCourse = false;
    boolean signed = false;

    TextView status, courseTitle, courseBody, hint;
    Button scanBtn;
    TextView reloadBtn;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        sp = getSharedPreferences("cfg", 0);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(GREEN);
        setContentView(root);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setBackgroundColor(BAR);
        bar.setPadding(dp(10), dp(8), dp(10), dp(8));
        root.addView(bar, new LinearLayout.LayoutParams(-1, -2));

        TextView back = tv("‹ 返回", 16, Color.WHITE, false);
        back.setPadding(dp(4), dp(4), dp(12), dp(4));
        back.setOnClickListener(v -> finish());
        bar.addView(back);

        TextView title = tv("签到考勤", 18, Color.WHITE, true);
        title.setGravity(Gravity.CENTER);
        bar.addView(title, new LinearLayout.LayoutParams(0, -2, 1));

        reloadBtn = tv("刷新", 15, Color.WHITE, false);
        reloadBtn.setPadding(dp(12), dp(4), dp(4), dp(4));
        reloadBtn.setOnClickListener(v -> load());
        bar.addView(reloadBtn);

        ScrollView scroll = new ScrollView(this);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));

        LinearLayout pad = new LinearLayout(this);
        pad.setOrientation(LinearLayout.VERTICAL);
        pad.setGravity(Gravity.CENTER_HORIZONTAL);
        pad.setPadding(dp(20), dp(22), dp(20), dp(30));
        scroll.addView(pad, new LinearLayout.LayoutParams(-1, -2));

        status = tv("正在登录易广金…", 13, 0xE6FFFFFF, false);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, 0, 0, dp(14));
        pad.addView(status);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(round(Color.WHITE, 16));
        card.setPadding(dp(18), dp(18), dp(18), dp(18));
        pad.addView(card, new LinearLayout.LayoutParams(-1, -2));

        courseTitle = tv("正在检测课程…", 19, 0xFF222222, true);
        courseTitle.setGravity(Gravity.CENTER);
        card.addView(courseTitle);

        courseBody = tv("", 14, 0xFF555555, false);
        courseBody.setGravity(Gravity.CENTER);
        courseBody.setPadding(0, dp(10), 0, 0);
        courseBody.setLineSpacing(dp(4), 1f);
        card.addView(courseBody);

        scanBtn = pill("扫码签到", Color.WHITE, 24, 17);
        scanBtn.setTextColor(0xFF2E7D32);
        scanBtn.setEnabled(false);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(dp(230), dp(48));
        slp.topMargin = dp(20);
        pad.addView(scanBtn, slp);
        scanBtn.setOnClickListener(v -> startScan());

        hint = tv("", 12, 0xCCFFFFFF, false);
        hint.setGravity(Gravity.CENTER);
        hint.setPadding(dp(10), dp(14), dp(10), 0);
        pad.addView(hint);

        TextView testCam = tv("测试相机（不会提交）", 12, 0xCCFFFFFF, false);
        testCam.setPadding(dp(10), dp(20), dp(10), 0);
        testCam.setOnClickListener(v -> startActivityForResult(new Intent(this, ScanActivity.class), REQ_TEST));
        pad.addView(testCam);

        load();
    }

    String token() {
        return sp.getString("userToken", "");
    }

    void load() {
        if (loading) return;
        loading = true;
        hasCourse = false;
        signed = false;
        scanBtn.setEnabled(false);
        scanBtn.setText("扫码签到");
        courseTitle.setText("正在检测课程…");
        courseBody.setText("");
        hint.setText("");
        status.setText("正在登录易广金…");
        final String tok = token();
        if (tok.isEmpty()) {
            loading = false;
            status.setText("还没有填写 token，请返回主界面填写");
            return;
        }
        new Thread(() -> {
            try {
                client = new YgjClient();
                sid = client.prepare(tok, java.util.UUID.randomUUID().toString(), android.os.Build.MODEL);

                JSONObject sch = getJson(YgjClient.BASE
                        + "/Handler/sign.ashx?flag=getStuInfoSchedule&studentID=" + sid);
                if (sch.optInt("code") != 0) throw new Exception("获取课表失败：" + sch.optString("msg"));
                JSONObject d = sch.getJSONObject("data");
                String yearIn = d.optString("yearIn", "2025");
                String school = d.optString("school", "清远校区");
                int startSignMin = d.optInt("startSignMin", 10);
                String xn = d.optString("xn"), xnxq = d.optString("xnxq");
                int week = weekNum(d.optString("firstWeekDate"));
                int g = grade(yearIn);
                JSONArray all = d.optJSONArray("scheduleInfo");
                JSONArray mine = new JSONArray();
                if (all != null) {
                    for (int i = 0; i < all.length(); i++) {
                        JSONObject it = all.optJSONObject(i);
                        if (it == null) continue;
                        if (!String.valueOf(g).equals(it.optString("grade"))) continue;
                        String ts, te;
                        if ("广州校本部".equals(school)) { ts = it.optString("timeS"); te = it.optString("timeE"); }
                        else if ("肇庆校区".equals(school)) { ts = it.optString("zqTimeS"); te = it.optString("zqTimeE"); }
                        else { ts = it.optString("qyTimeS"); te = it.optString("qyTimeE"); }
                        JSONObject m = new JSONObject();
                        m.put("timeS", ts);
                        m.put("timeE", te);
                        m.put("jc", it.optString("lessonTime").replace("第", "").replace("小节", ""));
                        mine.put(m);
                    }
                }
                schedule = mine;

                String now = hhmmPlus(startSignMin);
                String jc = "-1", startTime = "00:00";
                for (int i = 0; i < mine.length(); i++) {
                    JSONObject it = mine.getJSONObject(i);
                    if (now.compareTo(it.optString("timeS")) >= 0 && now.compareTo(it.optString("timeE")) <= 0) {
                        jc = it.optString("jc");
                        startTime = it.optString("timeS");
                        break;
                    }
                }

                Map<String, String> p = YgjClient.mapOf(
                        "studentID", sid,
                        "grade", String.valueOf(g),
                        "thisWeek", String.valueOf(week),
                        "jc", jc,
                        "xn", xn,
                        "xnxq", xnxq,
                        "startSignMin", String.valueOf(startSignMin),
                        "stopSignMin", d.optString("stopSignMin", "15"),
                        "lateSignMin", d.optString("lateSignMin", "2"),
                        "startTime", startTime,
                        "school", school);
                JSONObject cur = postJson(YgjClient.BASE + "/Handler/sign.ashx?flag=getCurrentCourse", p);
                if (cur.optInt("code") == 0 && cur.optJSONArray("data") != null
                        && cur.optJSONArray("data").length() > 0) {
                    JSONObject c = cur.getJSONArray("data").getJSONObject(0);
                    final String body = "班级：" + c.optString("BJMC") + "\n"
                            + "老师：" + c.optString("SKJSMC") + "\n"
                            + "节次：第" + c.optString("DDJ") + "节\n"
                            + "时间：" + c.optString("startTime") + " ~ " + c.optString("endTime");
                    final String name = c.optString("KCMC", "当前课程");
                    ui.post(() -> {
                        hasCourse = true;
                        loading = false;
                        courseTitle.setText(name);
                        courseBody.setText(body);
                        scanBtn.setEnabled(true);
                        status.setText("请扫老师屏幕/黑板上的二维码");
                        hint.setText("扫码后会自动提交签到");
                    });
                } else {
                    ui.post(() -> {
                        loading = false;
                        courseTitle.setText("无需签到考勤！");
                        courseBody.setText("当前没有需要签到的课程。");
                        scanBtn.setEnabled(false);
                        status.setText("非上课时间");
                        hint.setText("上课时再点右上角刷新");
                    });
                }
            } catch (Exception e) {
                final String msg = e.getMessage() == null ? "加载失败" : e.getMessage();
                ui.post(() -> {
                    loading = false;
                    String m = "TOKEN_EXPIRED".equals(msg) ? "token 已失效，请回主界面更换 token" : msg;
                    status.setText(m);
                    courseTitle.setText("加载失败");
                    courseBody.setText("");
                    hint.setText("点右上角刷新重试");
                });
            }
        }).start();
    }

    void startScan() {
        if (!hasCourse || signed) return;
        startActivityForResult(new Intent(this, ScanActivity.class), REQ_SCAN);
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_TEST) {
            if (res == RESULT_OK && data != null && data.getStringExtra("qr") != null) {
                String qr = data.getStringExtra("qr");
                String show = qr.length() > 300 ? qr.substring(0, 300) + "…" : qr;
                new AlertDialog.Builder(this).setTitle("扫码测试成功").setMessage(show)
                        .setPositiveButton("好", null).show();
            } else {
                status.setText("已取消扫码");
            }
            return;
        }
        if (req != REQ_SCAN) return;
        if (res == RESULT_OK && data != null && data.getStringExtra("qr") != null) {
            submit(data.getStringExtra("qr"));
        } else {
            status.setText("已取消扫码");
        }
    }

    void submit(String raw) {
        status.setText("正在提交签到…");
        scanBtn.setEnabled(false);
        new Thread(() -> {
            try {
                String code = raw == null ? "" : raw.trim();
                int i = code.indexOf("qrcode=");
                if (i >= 0) code = code.substring(i + 7);
                if (code.length() <= 32) throw new Exception("二维码内容不正确");
                String key = code.substring(code.length() - 32);
                String content = code.substring(0, code.length() - 32);
                Map<String, String> p = YgjClient.mapOf(
                        "key", key, "content", content, "studentID", sid, "type", "1");
                JSONObject r = postJson(YgjClient.BASE + "/Handler/sign.ashx?flag=saveSignNew2&studentID=" + sid, p);
                int c = r.optInt("code");
                if (c == 0 || c == 2) {
                    ui.post(() -> {
                        signed = true;
                        scanBtn.setEnabled(false);
                        scanBtn.setText("已完成签到");
                        status.setText("签到成功");
                        hint.setText(r.optString("msg", ""));
                    });
                } else {
                    final String m = r.optString("msg", "签到失败");
                    ui.post(() -> {
                        status.setText("签到失败：" + m);
                        scanBtn.setEnabled(true);
                    });
                }
            } catch (Exception e) {
                final String m = e.getMessage() == null ? "签到失败" : e.getMessage();
                ui.post(() -> {
                    status.setText(m);
                    scanBtn.setEnabled(true);
                });
            }
        }).start();
    }

    JSONObject getJson(String url) throws Exception {
        YgjClient.Resp r = client.req("GET", url, null, null);
        return new JSONObject(r.body);
    }

    JSONObject postJson(String url, Map<String, String> form) throws Exception {
        YgjClient.Resp r = client.req("POST", url, YgjClient.form(form), null);
        return new JSONObject(r.body);
    }

    static String hhmmPlus(int minutes) {
        Calendar c = Calendar.getInstance();
        c.add(Calendar.MINUTE, minutes);
        return String.format(Locale.US, "%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE));
    }

    static int grade(String yearIn) {
        int y;
        try { y = Integer.parseInt(yearIn.trim()); } catch (Exception e) { y = 2025; }
        Calendar c = Calendar.getInstance();
        int year = c.get(Calendar.YEAR);
        int month = c.get(Calendar.MONTH) + 1;
        return month >= 9 ? year - y + 1 : year - y;
    }

    static int weekNum(String firstWeekDate) {
        try {
            SimpleDateFormat f = new SimpleDateFormat("yyyy/M/d H:mm:ss", Locale.US);
            Date d = f.parse(firstWeekDate.trim());
            Calendar start = Calendar.getInstance();
            start.setTime(d);
            start.set(Calendar.HOUR_OF_DAY, 0);
            start.set(Calendar.MINUTE, 0);
            start.set(Calendar.SECOND, 0);
            start.set(Calendar.MILLISECOND, 0);
            int dow = start.get(Calendar.DAY_OF_WEEK);
            int shift = dow == Calendar.SUNDAY ? -6 : Calendar.MONDAY - dow;
            start.add(Calendar.DAY_OF_MONTH, shift);
            Calendar now = Calendar.getInstance();
            now.set(Calendar.HOUR_OF_DAY, 0);
            now.set(Calendar.MINUTE, 0);
            now.set(Calendar.SECOND, 0);
            now.set(Calendar.MILLISECOND, 0);
            long days = (now.getTimeInMillis() - start.getTimeInMillis()) / 86400000L;
            int w = (int) Math.ceil((days + 1) / 7.0);
            return Math.max(w, 1);
        } catch (Exception e) {
            return 1;
        }
    }

    int dp(float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    TextView tv(String s, float size, int color, boolean bold) {
        TextView v = new TextView(this);
        v.setText(s);
        v.setTextSize(size);
        v.setTextColor(color);
        if (bold) v.setTypeface(v.getTypeface(), android.graphics.Typeface.BOLD);
        return v;
    }

    Button pill(String s, int color, float radiusDp, float size) {
        Button b = new Button(this);
        b.setText(s);
        b.setTextSize(size);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setBackground(round(color, radiusDp));
        b.setPadding(0, 0, 0, 0);
        return b;
    }

    GradientDrawable round(int color, float radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }
}
