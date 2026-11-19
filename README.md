# FUCK-GDUF

> 出校码（GDUF）——广东金融学院易广金出入凭证小工具。

一个非官方的个人小工具，用来把广东金融学院「易广金」的出入凭证流程缩短成一次点击：

```
打开 App → 点「生成凭证」 → 出示二维码
```

原来的流程是：易班 App → 易广金 → 出入申报 → 右下角「常规出入」 → 生成二维码。

> 本项目与学校、易班官方无关，仅供个人学习和技术研究使用。请遵守学校出入、请假、考勤等相关规定。

## 功能

- **iOS / Android**：填入一次易班 App 的 token，之后点「生成凭证」直接出码，60 秒自动刷新。
- **出/入方向**：出校后再次生成会自动变成「入校凭证」，跟随服务端返回的方向。
- **跨天返校**：可按学校流程提交「出校超时（申请进校）」并生成入校码。
- **签到考勤**：上课时间显示课程信息，调用相机扫描班委提供的签到二维码；非上课时间显示「无需签到考勤」。
- **Scriptable**：一个单文件 JS 版本，不需要签名、不需要越狱，配合快捷指令可以放到桌面。

## 目录

```
ios/         Objective-C + UIKit 源码，Windows/Linux 下交叉编译出未签名 IPA
android/     纯 Java 单 Activity 源码，Android Studio 之外的命令行构建
scriptable/  Scriptable 单文件脚本（含二维码库）
```

## 使用

### iOS（未签名 IPA）

1. 下载 Releases 里的 `FUCK-GDUF-ios-v15.ipa`。
2. 用全能签 / Sideloadly / AltStore 等工具自签并安装（需要 iOS 15 及以上）。
3. 首次打开会要求粘贴 token（见下文「token 怎么来」）。
4. 点「生成凭证」，出示二维码；二维码每 60 秒自动刷新。
5. 更新版本时，用同一张签名证书覆盖安装；换证书需要先卸载。

### Android（APK）

1. 下载 Releases 里的 `FUCK-GDUF-android-v1.6.apk`。
2. 允许安装未知来源应用，安装（minSdk 26 / Android 8.0+）。
3. 首次打开粘贴 token，点「生成凭证」。
4. 主界面还有「签到考勤」：上课时间进入后点「扫码签到」，调用相机扫班委的二维码。

> v1.6 更换了签名证书。如果你装过 v1.5 或更早版本，需要先卸载旧版再装，否则会提示签名不一致。

### Scriptable（不想装 IPA 的话）

1. App Store 安装 [Scriptable](https://scriptable.app/)（免费）。
2. 把 `scriptable/gduf-scriptable.js` 放到「文件」App 的 `iCloud Drive/Scriptable/` 目录。
3. 打开 Scriptable，运行 `gduf-scriptable`，首次粘贴 token。
4. 想放到桌面：新建快捷指令 → 添加 Scriptable 的 **Run Script**（不是 Run Inline Script）→ 选择 `gduf-scriptable` → 关闭「运行时显示」→ 添加「快速查看」动作 → 重命名为「出校码」→ 长按「添加到主屏幕」。

> Scriptable 版发布的是 v4（`gduf-scriptable.js`，68,954 B）。v5 的改动没有采用，v4 是实测可用的版本。

## token 怎么来

这个 token 是**易班 App 的登录态**，32 位十六进制字符串，出现在易广金轻应用的请求 Cookie 里：

```
Cookie: client=iOS; loginToken=<32位token>; yiban_user_token=<同一个token>
```

用 ProxyPin（或 Stream）抓一次即可：

1. 手机安装 ProxyPin，开始抓包，并按提示安装/信任 CA 证书。
2. 打开易班 App → 易广金 → 出入申报 → 常规出入，停在二维码页面。
3. 在 ProxyPin 里找 `f.yiban.cn` 的请求（`iapp378946` 或 `iapp/index`）。
4. 打开请求头里的 `Cookie`，复制 `loginToken=` 后面的 32 位字符串。
5. 粘贴到 App / Scriptable 里，点开始使用。

注意：

- token 只保存在本机（iOS Keychain / Android SharedPreferences），不会上传到任何服务器，本项目也没有后端。
- token 是**单会话**的：在另一台手机的易班 App 上登录，会让旧 token 失效，需要重新抓一次。
- 不要把 token 发给别人，它等同于你的易班登录态。

## 构建

### iOS

需要：

- LLVM 18（clang + ld64.lld）
- iPhoneOS SDK（iOS 27 的 SDK，需自行准备；仓库不包含，体积太大）
- Python 3

把 SDK 放到 `toolchain/sdk_fixed2/`，LLVM 放到 `toolchain/LLVM/`，然后：

```bash
bash ios/build.sh
# 产物：ios/build/GDUFQR.ipa（未签名）
```

`ios/build.sh` 里的路径是相对 `toolchain/` 的；如果你放在别处，改脚本顶部的 `SDK` / `CLANG` 即可。

### Android

需要：

- JDK 17+
- Android SDK（platform 36、build-tools 36）
- 环境变量 `ANDROID_SDK_ROOT` 或 `ANDROID_HOME`

签名密钥不放进仓库，用环境变量传入：

```bash
export ANDROID_SDK_ROOT=/path/to/Android/Sdk
export GDUF_KS_PASS='你的密钥库口令'
export GDUF_KEYSTORE='gduf-release.keystore'   # 可选
export GDUF_KEY_ALIAS='gduf'                   # 可选

bash android/build.sh
# 产物：android/build/GDUFQR.apk
```

第一次运行时，如果 `GDUF_KEYSTORE` 不存在，脚本会用 `keytool` 生成一个新的。请把生成出来的 keystore 和口令备份到仓库之外；丢了就无法给老用户发升级包。

## 安全与隐私

- 没有服务器，没有账号系统，token 只在本机内存和本地存储里。
- 二维码内容 = 服务端下发的一串凭证 + 当前 Unix 秒，每 60 秒重新取一次；无法离线伪造，也不建议截图长期保存。
- 请不要把 `keystore`、`keystore.local`、抓包文件（`.har`）、token 提交到仓库。
- 设备绑定：易广金只允许「当前绑定设备」刷新二维码；App 会自动读取账号已绑定的设备信息，不需要手动解绑。

## 已知限制

- 依赖易广金的非公开接口，学校改版后可能失效。
- 每次「生成凭证」会在学校系统里真实生成一条 5 分钟有效的常规出入记录，不要连续点。
- 同一账号同一时间只认一台设备的绑定；在另一台手机登录易班会让旧 token 失效。
- iOS 包未签名，需要自签；Android v1.6 换了新证书，旧版本需要卸载。

## 第三方

- [ZXing](https://github.com/zxing/zxing)（Apache-2.0）：安卓端二维码解码。
- [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator)（MIT）：Scriptable 端二维码生成。
- CoreImage（iOS 系统框架）：iOS 端二维码生成。

## License

MIT
