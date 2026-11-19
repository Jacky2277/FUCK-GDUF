#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>

static NSString *const kBase = @"https://ygj.gduf.edu.cn";
static NSString *const kDeviceUUID = @""; // 留空则由 getStudentDevice 取当前绑定设备，取不到时用随机 UUID
static NSString *const kAppUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 yiban_iOS/5.2.5(5104)";
static NSString *const kFixedToken = @"";
static NSString *const kYibanUA = @"Yiban-Pro";
static NSString *const kCookieKey = @"gduf_yiban_cookies_v1";

static NSString *ENC(NSString *s) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *PlainMsg(NSString *s) {
    if (!s.length) return @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
    return [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
}

static NSString *FormBody(NSDictionary *fields) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in fields) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", ENC(k), ENC([fields[k] description])]];
    }
    return [parts componentsJoinedByString:@"&"];
}

@interface GFResp : NSObject
@property (nonatomic) NSInteger status;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) NSURL *finalURL;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, readonly) NSString *text;
@property (nonatomic, copy) NSString *location;
@end

@implementation GFResp
- (NSString *)text {
    if (!self.data) return @"";
    NSString *s = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:self.data encoding:NSISOLatin1StringEncoding];
    return s ?: @"";
}
@end

@interface GFNoRedirect : NSObject <NSURLSessionTaskDelegate>
@end

@implementation GFNoRedirect
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}
@end

static GFResp *HTTP(NSString *method, NSString *url, NSDictionary *headers, NSData *body, BOOL allowRedirect) {
    GFResp *out = [GFResp new];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = method;
    req.timeoutInterval = 25;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (body && !headers[@"Content-Type"]) {
        [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    }
    if (headers[@"Cookie"]) {
        // 显式带 Cookie 时不要让系统再拼一份
        req.HTTPShouldHandleCookies = NO;
    }
    for (NSString *k in headers) [req setValue:headers[k] forHTTPHeaderField:k];
    if (body) req.HTTPBody = body;
    NSURLSession *session = [NSURLSession sharedSession];
    if (!allowRedirect) {
        static NSURLSession *noRedirSession;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
            noRedirSession = [NSURLSession sessionWithConfiguration:cfg delegate:[GFNoRedirect new] delegateQueue:nil];
        });
        session = noRedirSession;
    }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *d = nil; __block NSURLResponse *r = nil; __block NSError *e = nil;
    NSURLSessionDataTask *t = [session dataTaskWithRequest:req completionHandler:^(NSData *dd, NSURLResponse *rr, NSError *ee) {
        d = dd; r = rr; e = ee; dispatch_semaphore_signal(sem);
    }];
    [t resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    out.data = d; out.error = e;
    if ([r isKindOfClass:[NSHTTPURLResponse class]]) {
        out.status = ((NSHTTPURLResponse *)r).statusCode;
    }
    out.finalURL = r.URL;
    out.location = [((NSHTTPURLResponse *)r).allHeaderFields[@"Location"] copy];
    return out;
}

@interface QRViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) UIImageView *qrView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *countdownLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *refreshBtn;
@property (nonatomic, strong) UIButton *overdueBtn;
@property (nonatomic, strong) UIButton *diagBtn;
@property (nonatomic, strong) UIButton *logoutBtn;
@property (nonatomic, strong) UIView *loginCover;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UILabel *setupHint;
@property (nonatomic, strong) WKWebView *loginWeb;
@property (nonatomic, strong) UILabel *loginTitle;
@property (nonatomic, strong) WKWebView *ssoWeb;
@property (nonatomic) BOOL ssoRunning;
@property (nonatomic, copy) NSString *presetVerify;
@property (nonatomic, strong) NSTimer *ssoTimer;

@property (nonatomic, copy) NSString *studentID;
@property (nonatomic, copy) NSString *outSchoolID;
@property (nonatomic, copy) NSString *qrcodeStr;
@property (nonatomic, copy) NSString *studentName;
@property (nonatomic, strong) NSDate *endDate;
@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL loginShowing;
    @property (nonatomic, strong) UILabel *placeholderLabel;
    @property (nonatomic) BOOL hasQR;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic, strong) NSTimer *qrTimer;
@property (nonatomic, strong) NSTimer *loginPoll;
@property (nonatomic, strong) CIContext *ciContext;
@end

@interface SignViewController : UIViewController
@property (nonatomic, weak) QRViewController *host;
@end

@implementation QRViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.ciContext = [CIContext contextWithOptions:nil];
    self.view.backgroundColor = [UIColor colorWithRed:0.47 green:0.72 blue:0.26 alpha:1.0];

    self.titleLabel = [UILabel new];
    UILabel *title = self.titleLabel;
    title.text = @"出校凭证";
    title.font = [UIFont boldSystemFontOfSize:30];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    self.nameLabel = [UILabel new];
    self.nameLabel.font = [UIFont systemFontOfSize:16];
    self.nameLabel.textColor = UIColor.whiteColor;
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.numberOfLines = 0;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.nameLabel];

    UIView *card = [UIView new];
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 14;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    self.qrView = [UIImageView new];
    self.qrView.contentMode = UIViewContentModeScaleAspectFit;
    self.qrView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.qrView];

    self.placeholderLabel = [UILabel new];
    self.placeholderLabel.text = @"点击下方按钮\n生成凭证";
    self.placeholderLabel.numberOfLines = 2;
    self.placeholderLabel.textAlignment = NSTextAlignmentCenter;
    self.placeholderLabel.font = [UIFont systemFontOfSize:18];
    self.placeholderLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1];
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.placeholderLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.placeholderLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [self.placeholderLabel.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];

    self.countdownLabel = [UILabel new];
    self.countdownLabel.font = [UIFont boldSystemFontOfSize:16];
    self.countdownLabel.textColor = UIColor.whiteColor;
    self.countdownLabel.textAlignment = NSTextAlignmentCenter;
    self.countdownLabel.numberOfLines = 0;
    self.countdownLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.countdownLabel];

    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.diagBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.diagBtn setTitle:@"复制诊断信息" forState:UIControlStateNormal];
    [self.diagBtn setTitleColor:[UIColor colorWithWhite:1 alpha:0.75] forState:UIControlStateNormal];
    self.diagBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.diagBtn addTarget:self action:@selector(copyDiag) forControlEvents:UIControlEventTouchUpInside];
    self.diagBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.diagBtn];

    self.refreshBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.refreshBtn setTitle:@"刷新凭证" forState:UIControlStateNormal];
    [self.refreshBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.refreshBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.refreshBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    self.refreshBtn.layer.cornerRadius = 22;
    [self.refreshBtn addTarget:self action:@selector(doRefresh) forControlEvents:UIControlEventTouchUpInside];
    self.refreshBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.refreshBtn];

    self.overdueBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.overdueBtn setTitle:@"跨天返校（出校超时）" forState:UIControlStateNormal];
    [self.overdueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.overdueBtn.titleLabel.font = [UIFont systemFontOfSize:15];
    self.overdueBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
    self.overdueBtn.layer.cornerRadius = 22;
    [self.overdueBtn addTarget:self action:@selector(doOverdue) forControlEvents:UIControlEventTouchUpInside];
    self.overdueBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.overdueBtn];

    self.logoutBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.logoutBtn setTitle:@"更换 token" forState:UIControlStateNormal];
    [self.logoutBtn setTitleColor:[UIColor colorWithWhite:1 alpha:0.7] forState:UIControlStateNormal];
    self.logoutBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.logoutBtn addTarget:self action:@selector(doLogout) forControlEvents:UIControlEventTouchUpInside];
    self.logoutBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logoutBtn];

    UIButton *signTop = [UIButton buttonWithType:UIButtonTypeSystem];
    [signTop setTitle:@"签到考勤" forState:UIControlStateNormal];
    [signTop setTitleColor:[UIColor colorWithWhite:1 alpha:0.9] forState:UIControlStateNormal];
    signTop.titleLabel.font = [UIFont systemFontOfSize:13];
    [signTop addTarget:self action:@selector(doOpenSign) forControlEvents:UIControlEventTouchUpInside];
    signTop.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:signTop];
    [NSLayoutConstraint activateConstraints:@[
        [signTop.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [signTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [signTop.heightAnchor constraintEqualToConstant:32],
    ]];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:26],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.nameLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [card.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:18],
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.widthAnchor constraintEqualToConstant:300],
        [card.heightAnchor constraintEqualToConstant:300],
        [self.qrView.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [self.qrView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [self.qrView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.qrView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.countdownLabel.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:22],
        [self.countdownLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.countdownLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.countdownLabel.bottomAnchor constant:10],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [self.diagBtn.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:14],
        [self.diagBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.diagBtn.heightAnchor constraintEqualToConstant:20],
        [self.refreshBtn.topAnchor constraintEqualToAnchor:self.diagBtn.bottomAnchor constant:10],
        [self.refreshBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.refreshBtn.widthAnchor constraintEqualToConstant:180],
        [self.refreshBtn.heightAnchor constraintEqualToConstant:44],
        [self.overdueBtn.topAnchor constraintEqualToAnchor:self.refreshBtn.bottomAnchor constant:10],
        [self.overdueBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.overdueBtn.widthAnchor constraintEqualToConstant:200],
        [self.overdueBtn.heightAnchor constraintEqualToConstant:44],
        [self.logoutBtn.topAnchor constraintEqualToAnchor:self.overdueBtn.bottomAnchor constant:10],
        [self.logoutBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.logoutBtn.bottomAnchor constraintLessThanOrEqualToAnchor:g.bottomAnchor constant:-12],
    ]];

    self.nameLabel.text = @"正在加载…";
    self.countdownLabel.text = @"";
    self.statusLabel.text = @"";

    [self restoreCookies];
    if ([self savedToken].length) {
        [self showIdle];
    } else {
        [self showLogin];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)onForeground {
    if (!self.loginShowing && self.hasQR && self.qrcodeStr && self.endDate && [self.endDate timeIntervalSinceNow] < -5) {
        [self refreshAll];
    }
}

#pragma mark - Cookies

- (NSArray<NSHTTPCookie *> *)yibanCookies {
    NSMutableArray *a = [NSMutableArray array];
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([c.domain containsString:@"yiban.cn"]) [a addObject:c];
    }
    return a;
}

- (BOOL)hasYibanCookie {
    for (NSHTTPCookie *c in [self yibanCookies]) {
        if ([c.name isEqualToString:@"yiban_user_token"] && c.value.length > 0) return YES;
    }
    return NO;
}

- (void)saveCookies {
    NSMutableArray *arr = [NSMutableArray array];
    for (NSHTTPCookie *c in [self yibanCookies]) {
        [arr addObject:@{
            @"name": c.name, @"value": c.value, @"domain": c.domain, @"path": c.path,
            @"secure": @(c.isSecure), @"expires": c.expiresDate ?: [NSDate distantFuture],
        }];
    }
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:kCookieKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)restoreCookies {
    NSArray *arr = [[NSUserDefaults standardUserDefaults] arrayForKey:kCookieKey];
    for (NSDictionary *d in arr) {
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        p[NSHTTPCookieName] = d[@"name"] ?: @"";
        p[NSHTTPCookieValue] = d[@"value"] ?: @"";
        p[NSHTTPCookieDomain] = d[@"domain"] ?: @"";
        p[NSHTTPCookiePath] = d[@"path"] ?: @"/";
        p[NSHTTPCookieSecure] = [d[@"secure"] boolValue] ? @"TRUE" : @"";
        if (d[@"expires"]) p[NSHTTPCookieExpires] = d[@"expires"];
        NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:p];
        if (c) [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:c];
    }
}

- (void)clearCookies {
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([c.domain containsString:@"yiban.cn"] || [c.domain containsString:@"gduf.edu.cn"]) {
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
        }
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCookieKey];
}

- (void)copyWebCookies:(void (^)(BOOL))done {
    [[WKWebsiteDataStore defaultDataStore].httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        // 先清掉旧易班 Cookie，避免同名新旧两份互相污染
        for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
            if ([c.domain containsString:@"yiban.cn"]) {
                [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:c];
            }
        }
        BOOL found = NO;
        NSMutableDictionary *seen = [NSMutableDictionary dictionary];
        for (NSHTTPCookie *c in cookies) {
            if (![c.domain containsString:@"yiban.cn"]) continue;
            if (!c.name.length || !c.value.length) continue;
            if (seen[c.name]) continue;
            seen[c.name] = @1;
            // 统一放宽到 .yiban.cn，保证 f.yiban.cn 也能带上
            NSMutableDictionary *p = [NSMutableDictionary dictionary];
            p[NSHTTPCookieName] = c.name;
            p[NSHTTPCookieValue] = c.value;
            p[NSHTTPCookieDomain] = @".yiban.cn";
            p[NSHTTPCookiePath] = @"/";
            p[NSHTTPCookieSecure] = @"TRUE";
            if (c.expiresDate) p[NSHTTPCookieExpires] = c.expiresDate;
            NSHTTPCookie *nc = [NSHTTPCookie cookieWithProperties:p];
            if (nc) [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:nc];
            if ([c.name isEqualToString:@"yiban_user_token"] && c.value.length > 0) found = YES;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(found); });
    }];
}

- (void)setStudentCookie {
    NSDictionary *p = @{
        NSHTTPCookieName: @"studentID",
        NSHTTPCookieValue: self.studentID ?: @"",
        NSHTTPCookieDomain: @"ygj.gduf.edu.cn",
        NSHTTPCookiePath: @"/",
        NSHTTPCookieSecure: @"TRUE",
    };
    NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:p];
    if (c) [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:c];
}

#pragma mark - 登录界面

- (NSString *)savedToken {
    NSString *t = [[NSUserDefaults standardUserDefaults] stringForKey:@"userToken"];
    return t.length ? t : kFixedToken;
}

- (void)showLogin {
    if (self.loginShowing) return;
    self.loginShowing = YES;
    CGRect b = self.view.bounds;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    if (safeTop < 20 && self.view.window) safeTop = self.view.window.safeAreaInsets.top;
    if (safeTop < 20) safeTop = 62;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    if (safeBottom < 1) safeBottom = 0;

    self.loginCover = [[UIView alloc] initWithFrame:b];
    self.loginCover.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
    self.loginCover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.loginCover];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:b];
    sv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.loginCover addSubview:sv];

    CGFloat w = b.size.width - 48;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, safeTop + 36, w, 44)];
    title.text = @"出校码";
    title.font = [UIFont boldSystemFontOfSize:30];
    [sv addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(24, safeTop + 84, w, 24)];
    sub.text = @"首次使用需要填写一次易班 token";
    sub.font = [UIFont systemFontOfSize:15];
    sub.textColor = [UIColor colorWithWhite:0.35 alpha:1];
    [sv addSubview:sub];

    CGFloat cardW = b.size.width - 32;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, safeTop + 124, cardW, 10)];
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 14;
    [sv addSubview:card];

    UILabel *step = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, cardW - 32, 0)];
    step.numberOfLines = 0;
    step.font = [UIFont systemFontOfSize:14];
    step.textColor = [UIColor colorWithWhite:0.25 alpha:1];
    step.text = @"1. 安装抓包工具（Stream / ProxyPin）\n2. 打开易班 App → 易广金 → 出入申报 → 常规出入\n3. 在抓包记录里找 f.yiban.cn 的请求\n4. 复制请求头里的 loginToken（32 位）\n5. 粘贴到下面，点“开始使用”";
    [step sizeToFit];
    step.frame = CGRectMake(16, 16, cardW - 32, step.frame.size.height);
    [card addSubview:step];

    self.tokenField = [[UITextField alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(step.frame) + 18, cardW - 32, 46)];
    self.tokenField.placeholder = @"粘贴 32 位 user token";
    self.tokenField.borderStyle = UITextBorderStyleRoundedRect;
    self.tokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.tokenField.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
    [card addSubview:self.tokenField];

    UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
    paste.frame = CGRectMake(16, CGRectGetMaxY(self.tokenField.frame) + 12, 90, 44);
    [paste setTitle:@"粘贴" forState:UIControlStateNormal];
    [paste addTarget:self action:@selector(pasteToken) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:paste];

    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    go.frame = CGRectMake(112, CGRectGetMaxY(self.tokenField.frame) + 12, cardW - 128, 44);
    [go setTitle:@"开始使用" forState:UIControlStateNormal];
    [go setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    go.backgroundColor = [UIColor colorWithRed:0.11 green:0.55 blue:0.20 alpha:1];
    go.layer.cornerRadius = 10;
    go.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [go addTarget:self action:@selector(saveTokenFromField) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:go];

    self.setupHint = [[UILabel alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(go.frame) + 10, cardW - 32, 0)];
    self.setupHint.numberOfLines = 0;
    self.setupHint.font = [UIFont systemFontOfSize:12];
    self.setupHint.textColor = [UIColor redColor];
    [card addSubview:self.setupHint];

    card.frame = CGRectMake(16, safeTop + 124, cardW, CGRectGetMaxY(self.setupHint.frame) + 14);

    UIButton *help = [UIButton buttonWithType:UIButtonTypeSystem];
    help.frame = CGRectMake(16, CGRectGetMaxY(card.frame) + 10, cardW, 40);
    [help setTitle:@"详细教程" forState:UIControlStateNormal];
    help.titleLabel.font = [UIFont systemFontOfSize:14];
    [help addTarget:self action:@selector(showTokenHelp) forControlEvents:UIControlEventTouchUpInside];
    [sv addSubview:help];

    if ([self savedToken].length) {
        UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
        back.frame = CGRectMake(b.size.width - 78, safeTop + 8, 62, 36);
        [back setTitle:@"返回" forState:UIControlStateNormal];
        [back addTarget:self action:@selector(hideLogin) forControlEvents:UIControlEventTouchUpInside];
        [sv addSubview:back];
    }

    sv.contentSize = CGSizeMake(b.size.width, CGRectGetMaxY(help.frame) + 30 + safeBottom);
}

- (void)pasteToken {
    NSString *s = UIPasteboard.generalPasteboard.string ?: @"";
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length) self.tokenField.text = s;
}

- (void)saveTokenFromField {
    NSString *t = [self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length < 32) {
        self.setupHint.text = @"token 应该是 32 位十六进制字符，检查一下是否复制完整";
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:t forKey:@"userToken"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self hideLogin];
    [self showIdle];
}

- (void)showTokenHelp {
    NSString *msg = @"1. App Store 搜索并下载 ProxyPin（已安装可跳过）\n"
                     "2. 打开 ProxyPin，点「开始抓包」；首次使用按提示安装证书，再到 设置→通用→关于本机→证书信任设置 打开 ProxyPin\n"
                     "3. 保持抓包，打开易班 App → 易广金 → 出入申报 → 常规出入，停在二维码页\n"
                     "4. 回 ProxyPin 停止抓包，找到 f.yiban.cn 的请求（地址里带 iapp378946 或 iapp/index）\n"
                     "5. 点开请求 → 请求头 → 找到 Cookie，复制 loginToken= 后面那 32 位字符（到分号为止，不要带空格）\n"
                     "6. 粘贴到输入框，点「开始使用」\n\n"
                     "token 只保存在本机，不会上传；失效时 App 会提示重新抓取。\n"
                     "抓不到 f.yiban.cn：确认停在二维码页，清空记录后重抓一次。";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"怎么获取 token" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)hideLogin {
    [self.loginPoll invalidate];
    self.loginPoll = nil;
    [self.loginCover removeFromSuperview];
    self.loginCover = nil;
    self.loginWeb = nil;
    self.loginShowing = NO;
    [self.view layoutIfNeeded];
    self.view.hidden = NO;
}

- (NSInteger)importCookieString:(NSString *)s {
    NSInteger n = 0;
    for (NSString *part in [s componentsSeparatedByString:@";"]) {
        NSString *kv = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange eq = [kv rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *name = [kv substringToIndex:eq.location];
        NSString *value = [kv substringFromIndex:eq.location + 1];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length || !value.length) continue;
        NSDictionary *p = @{
            NSHTTPCookieName: name,
            NSHTTPCookieValue: value,
            NSHTTPCookieDomain: @".yiban.cn",
            NSHTTPCookiePath: @"/",
            NSHTTPCookieSecure: @"TRUE",
        };
        NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:p];
        if (c) {
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:c];
            n++;
        }
    }
    return n;
}

- (void)showCookieImport {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"粘贴 Cookie"
        message:@"从易班 App 的请求头里复制 Cookie（需含 yiban_user_token）"
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"yiban_user_token=...; YB_SSID=...";
        tf.font = [UIFont systemFontOfSize:13];
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *txt = ac.textFields.firstObject.text ?: @"";
        NSInteger n = [self importCookieString:txt];
        if (n <= 0) {
            self.statusLabel.text = @"Cookie 格式不正确";
            return;
        }
        [self saveCookies];
        [self hideLogin];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self refreshAll];
        });
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)loginCheckNow {
    if (!self.loginShowing) return;
    [self copyWebCookies:^(BOOL ok) {
        if (ok) {
            [self saveCookies];
            [self hideLogin];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self refreshAll];
            });
        }
    }];
}

- (void)doLogout {
    [self clearCookies];
    [[WKWebsiteDataStore defaultDataStore].httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        for (NSHTTPCookie *c in cookies) {
            if ([c.domain containsString:@"yiban.cn"] || [c.domain containsString:@"gduf.edu.cn"]) {
                [[WKWebsiteDataStore defaultDataStore].httpCookieStore deleteCookie:c completionHandler:nil];
            }
        }
    }];
    [self.tickTimer invalidate];
    [self.qrTimer invalidate];
    self.qrcodeStr = nil;
    self.qrView.image = nil;
    self.nameLabel.text = @"未登录";
    self.countdownLabel.text = @"";
    self.statusLabel.text = @"";
    [self showLogin];
}

#pragma mark - 易班网页 SSO

- (void)seedWebCookiesThen:(void (^)(void))done {
    WKHTTPCookieStore *store = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
    NSMutableArray *list = [NSMutableArray array];
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([c.domain containsString:@"yiban.cn"] && c.name.length && c.value.length) [list addObject:c];
    }
    if (!list.count) { done(); return; }
    dispatch_group_t g = dispatch_group_create();
    for (NSHTTPCookie *c in list) {
        dispatch_group_enter(g);
        [store setCookie:c completionHandler:^{ dispatch_group_leave(g); }];
    }
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        done();
    });
}

- (void)startWebSSO {
    if (self.ssoRunning) return;
    self.ssoRunning = YES;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.text = @"正在通过易班网页获取登录凭证…";
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    CGRect b = self.view.bounds;
    self.ssoWeb = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, MAX(b.size.height, 320)) configuration:cfg];
    self.ssoWeb.customUserAgent = @"Yiban-Pro";
    self.ssoWeb.navigationDelegate = self;
    self.ssoWeb.alpha = 0.01;
    self.ssoWeb.userInteractionEnabled = NO;
    [self.view addSubview:self.ssoWeb];
    [self.ssoTimer invalidate];
    self.ssoTimer = [NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(ssoTimeout) userInfo:nil repeats:NO];
    __weak typeof(self) weakSelf = self;
    [self seedWebCookiesThen:^{
        [weakSelf.ssoWeb loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://f.yiban.cn/iapp378946"]]];
    }];
}

- (void)stopWebSSO {
    self.ssoRunning = NO;
    [self.ssoTimer invalidate];
    self.ssoTimer = nil;
    [self.ssoWeb stopLoading];
    [self.ssoWeb removeFromSuperview];
    self.ssoWeb = nil;
}

- (void)ssoTimeout {
    if (!self.ssoRunning) return;
    NSString *u = self.ssoWeb.URL.absoluteString ?: @"";
    [self stopWebSSO];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.text = [NSString stringWithFormat:@"网页获取凭证超时（%@）", u.length ? u : @"无响应"];
}

- (void)finishWebSSOWithVerify:(NSString *)verify {
    if (!self.ssoRunning || !verify.length) return;
    [self stopWebSSO];
    [self hideLogin];
    self.presetVerify = verify;
    self.statusLabel.text = @"已取得登录凭证，正在生成二维码…";
    [self refreshAll];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (webView == self.ssoWeb) {
        NSURL *u = action.request.URL;
        if ([u.host isEqualToString:@"ygj.gduf.edu.cn"]) {
            NSString *v = [self queryValue:u.query key:@"verify_request"];
            if (v.length) {
                decisionHandler(WKNavigationActionPolicyCancel);
                [self finishWebSSOWithVerify:v];
                return;
            }
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (webView != self.ssoWeb) return;
    NSURL *u = webView.URL;
    if ([u.host containsString:@"f.yiban.cn"]) {
        __weak typeof(self) weakSelf = self;
        [webView evaluateJavaScript:@"document.body.innerText" completionHandler:^(id r, NSError *e) {
            NSString *t = [r isKindOfClass:[NSString class]] ? r : @"";
            t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            t = [t stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if (t.length > 60) t = [t substringToIndex:60];
            if (t.length && weakSelf.ssoRunning) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"易班跳转：%@", t];
            }
        }];
        return;
    }
    if (![u.host isEqualToString:@"ygj.gduf.edu.cn"]) return;
    NSString *v = [self queryValue:u.query key:@"verify_request"];
    if (v.length) { [self finishWebSSOWithVerify:v]; return; }
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id r, NSError *e) {
        NSString *html = [r isKindOfClass:[NSString class]] ? r : @"";
        NSString *vv = [weakSelf regexGroup:html pattern:@"verify_request=([0-9a-fA-F]{32,})"];
        if (!vv.length) vv = [weakSelf regexGroup:html pattern:@"var\\s+verify_request\\s*=\\s*\"([^\"]+)\""];
        if (vv.length) [weakSelf finishWebSSOWithVerify:vv];
    }];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (webView != self.ssoWeb || !self.ssoRunning) return;
    self.statusLabel.text = [NSString stringWithFormat:@"网页加载失败：%@", error.localizedDescription ?: @"未知错误"];
}

#pragma mark - 主流程

- (void)doRefresh {
    [self refreshAll];
}

- (void)copyDiag {
    [UIPasteboard generalPasteboard].string = self.statusLabel.text ?: @"";
    [self.diagBtn setTitle:@"已复制，去粘贴吧" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.diagBtn setTitle:@"复制诊断信息" forState:UIControlStateNormal];
    });
}

- (void)refreshAll {
    if (self.busy) return;
    if (![self savedToken].length) { [self showLogin]; return; }
    self.busy = YES;
    self.statusLabel.text = @"正在连接学校服务器…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        NSDictionary *res = [self bootstrap:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (!res) {
                if ([err isEqualToString:@"NEED_LOGIN"]) {
                    [self clearCookies];
                    [self showLogin];
                    self.setupHint.text = @"token 已失效，请重新抓一次并粘贴";
                } else {
                    self.statusLabel.font = [UIFont systemFontOfSize:(err.length > 70 ? 11 : 13)];
                    self.statusLabel.text = err.length ? err : @"获取失败，请点刷新重试";
                }
                return;
            }
            [self applyResult:res];
        });
    });
}

- (NSString *)yibanCookieHeader {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSDate *now = [NSDate date];
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if (![c.domain containsString:@"yiban.cn"] || !c.name.length || !c.value.length) continue;
        if (c.expiresDate && [c.expiresDate timeIntervalSinceDate:now] < 0) continue;
        NSHTTPCookie *old = m[c.name];
        if (old && old.expiresDate && c.expiresDate && [old.expiresDate compare:c.expiresDate] == NSOrderedDescending) continue;
        m[c.name] = c;
    }
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in m) [a addObject:[NSString stringWithFormat:@"%@=%@", k, ((NSHTTPCookie *)m[k]).value]];
    return [a componentsJoinedByString:@"; "];
}

- (NSString *)yibanCookieNames {
    NSMutableArray *a = [NSMutableArray array];
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([c.domain containsString:@"yiban.cn"] && c.name.length) [a addObject:c.name];
    }
    return a.count ? [a componentsJoinedByString:@","] : @"无";
}

- (NSString *)appCookieHeaderWithToken:(NSString *)token overrideToken:(BOOL)override {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if (![c.domain containsString:@"yiban.cn"] || !c.name.length || !c.value.length) continue;
        if ([c.name isEqualToString:@"client"] || [c.name isEqualToString:@"loginToken"]) continue;
        if (override && [c.name isEqualToString:@"yiban_user_token"]) continue;
        m[c.name] = c.value;
    }
    m[@"client"] = @"iOS";
    m[@"loginToken"] = token;
    if (override) m[@"yiban_user_token"] = token;
    if (!m[@"yiban_user_token"]) m[@"yiban_user_token"] = token;
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in m) [a addObject:[NSString stringWithFormat:@"%@=%@", k, m[k]]];
    return [a componentsJoinedByString:@"; "];
}

- (NSString *)absoluteURL:(NSString *)u base:(NSString *)base {
    if (!u.length) return nil;
    NSURL *b = [NSURL URLWithString:base];
    NSURL *r = [NSURL URLWithString:u relativeToURL:b];
    return r.absoluteString;
}

- (NSDictionary *)bootstrap:(NSString **)err {
    NSString *verify = nil;
    GFResp *fr = nil;
    NSString *token = [self savedToken];
    if (!token.length) {
        *err = @"NEED_LOGIN"; return nil;
    }

    // 2. 以易班 App 内 WebView 的身份访问轻应用，拿 verify_request
    //    关键：UA 用 yiban_iOS、AppVersion 5.2.5，Cookie 里必须有 client=iOS、loginToken、yiban_user_token
    NSDictionary *base = @{
        @"User-Agent": kAppUA,
        @"AppVersion": @"5.2.5",
        @"Authorization": [@"Bearer " stringByAppendingString:token],
        @"loginToken": token,
        @"Accept": @"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        @"Accept-Language": @"zh-CN,zh-Hans;q=0.9",
        @"Sec-Fetch-Site": @"none",
        @"Sec-Fetch-Mode": @"navigate",
        @"Sec-Fetch-Dest": @"document",
    };

    NSMutableString *rep = [NSMutableString string];
    NSArray *cookieModes = @[[self appCookieHeaderWithToken:token overrideToken:NO],
                             [self appCookieHeaderWithToken:token overrideToken:YES]];
    for (NSUInteger i = 0; i < cookieModes.count; i++) {
        if (i) [NSThread sleepForTimeInterval:0.8];
        NSMutableDictionary *h = [base mutableCopy];
        h[@"Cookie"] = cookieModes[i];
        NSString *u1 = @"https://f.yiban.cn/iapp378946";
        GFResp *r1 = HTTP(@"GET", u1, h, nil, NO);
        NSString *loc1 = [self absoluteURL:r1.location base:u1];
        GFResp *r2 = nil;
        NSString *finalLoc = loc1 ?: @"";
        if (loc1.length && ![loc1 containsString:@"verify_request="]) {
            r2 = HTTP(@"GET", loc1, h, nil, NO);
            NSString *loc2 = [self absoluteURL:r2.location base:loc1];
            if (loc2.length) finalLoc = loc2;
        }
        NSString *v = nil;
        NSURLComponents *uc = [NSURLComponents componentsWithString:finalLoc];
        for (NSURLQueryItem *it in uc.queryItems) {
            if ([it.name isEqualToString:@"verify_request"]) v = it.value;
        }
        if (!v.length) v = [self regexGroup:finalLoc pattern:@"verify_request=([0-9a-fA-F]{32,})"];
        if (!v.length) v = [self regexGroup:(r2 ?: r1).text pattern:@"verify_request=([0-9a-fA-F]{32,})"];
        GFResp *last = r2 ?: r1;
        fr = last;
        NSString *snip = [last.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        snip = [snip stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (snip.length > 40) snip = [snip substringToIndex:40];
        NSString *locSnip = finalLoc.length > 80 ? [finalLoc substringToIndex:80] : finalLoc;
        [rep appendFormat:@"[app%lu %ld/%ld err=%ld loc=%@ body=%@] ", (unsigned long)i, (long)r1.status, (long)last.status, (long)r1.error.code, locSnip, snip];
        if (v.length) { verify = v; break; }
        if ([last.text containsString:@"请勿频繁"]) { *err = @"请求太频繁，请 10 秒后再试"; return nil; }
    }
    if (!verify.length) {
        *err = [NSString stringWithFormat:@"未获取到 verify_request（Cookie: %@）。%@", [self yibanCookieNames], rep];
        return nil;
    }

    // 3. ygj 登录
    NSString *boundary = @"----WebKitFormBoundaryGDUFQRAPP";
    NSMutableData *mb = [NSMutableData data];
    [mb appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"loginToken\"\r\n\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [mb appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"verify_request\"\r\n\r\n%@\r\n", boundary, verify] dataUsingEncoding:NSUTF8StringEncoding]];
    [mb appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    GFResp *li = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/login.ashx?flag=login"], @{
        @"Content-Type": [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary],
        @"User-Agent": kAppUA,
        @"Origin": kBase,
        @"Referer": fr.finalURL.absoluteString ?: [kBase stringByAppendingString:@"/index.aspx"],
        @"X-Requested-With": @"XMLHttpRequest",
    }, mb, YES);
    NSDictionary *ij = [self json:li.data];
    if (![ij[@"code"] isEqual:@0]) {
        *err = [NSString stringWithFormat:@"学校登录失败：%@", ij[@"msg"] ?: @""];
        return nil;
    }
    NSString *goTo = ij[@"goToUrl"] ?: @"";
    NSString *sid = [self queryValue:goTo key:@"studentID"];
    if (!sid.length) {
        NSString *g = [self regexGroup:goTo pattern:@"studentID=(\\d+)"];
        sid = g;
    }
    if (!sid.length) { *err = @"未获取到学号"; return nil; }
    self.studentID = sid;
    [self setStudentCookie];
    if (goTo.length) {
        NSString *abs = [goTo hasPrefix:@"http"] ? goTo : [kBase stringByAppendingString:([goTo hasPrefix:@"/"] ? goTo : [@"/" stringByAppendingString:goTo])];
        HTTP(@"GET", abs, @{@"User-Agent": kAppUA, @"Referer": fr.finalURL.absoluteString ?: kBase}, nil, YES);
    }

    NSDictionary *yh = @{
        @"User-Agent": kAppUA,
        @"Origin": kBase,
        @"Referer": [kBase stringByAppendingFormat:@"/ygj2024/student-default.aspx?studentID=%@", sid],
        @"X-Requested-With": @"XMLHttpRequest",
    };
    NSString *hid = [kBase stringByAppendingString:@"/Handler/device.ashx?flag="];

    // 4. getNotice（必须先调用，服务端才会初始化会话设备态）
    GFResp *nt = HTTP(@"POST", [hid stringByAppendingString:@"getNotice"],
                      yh, [FormBody(@{@"studentID": sid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    if (![[self json:nt.data][@"code"] isEqual:@0]) { *err = @"初始化会话失败"; return nil; }

    // 5. 设备校验：沿用账号当前绑定设备的 uuid/机型（服务端按 deviceModel 精确判定，
    //    自己编的机型会被判"非绑定设备"，只能找辅导员解绑）
    NSString *devUUID = kDeviceUUID.length ? kDeviceUUID : [[NSUUID UUID] UUIDString];
    NSString *devModel = @"iPhone 17";
    NSString *devSys = @"27.0";
    NSString *devApp = @"5.2.5";
    GFResp *sd = HTTP(@"POST", [hid stringByAppendingString:@"getStudentDevice"],
                      yh, [FormBody(@{@"studentID": sid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *sdj = [self json:sd.data];
    if ([sdj[@"code"] isEqual:@0] && [sdj[@"data"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *d in sdj[@"data"]) {
            if (![d isKindOfClass:[NSDictionary class]] || ![d[@"state"] isEqual:@"1"]) continue;
            if ([d[@"uuid"] isKindOfClass:[NSString class]] && [d[@"uuid"] length]) devUUID = d[@"uuid"];
            if ([d[@"deviceModel"] isKindOfClass:[NSString class]] && [d[@"deviceModel"] length]) devModel = d[@"deviceModel"];
            if ([d[@"systemVersion"] isKindOfClass:[NSString class]] && [d[@"systemVersion"] length]) devSys = d[@"systemVersion"];
            if ([d[@"appVersion"] isKindOfClass:[NSString class]] && [d[@"appVersion"] length]) devApp = d[@"appVersion"];
            break;
        }
    }
    NSString *devJson = [NSString stringWithFormat:@"{\"uuid\":\"%@\",\"appVersion\":\"%@\",\"deviceModel\":\"%@\",\"systemVersion\":\"%@\"}",
                         devUUID, devApp, devModel, devSys];
    GFResp *bd = HTTP(@"POST", [hid stringByAppendingString:@"checkBindDevice"],
                      yh, [FormBody(@{@"deviceData": devJson, @"autoBind": @"false"}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *bj = [self json:bd.data];
    if ([bj[@"code"] isEqual:@1]) {
        // 从未绑定过：用本机随机 uuid 走 autoBind
        NSString *ownJson = [NSString stringWithFormat:@"{\"uuid\":\"%@\",\"appVersion\":\"5.2.5\",\"deviceModel\":\"iPhone\",\"systemVersion\":\"27.0\"}",
                             [[NSUUID UUID] UUIDString]];
        GFResp *bd2 = HTTP(@"POST", [hid stringByAppendingString:@"checkBindDevice"],
                           yh, [FormBody(@{@"deviceData": ownJson, @"autoBind": @"true"}) dataUsingEncoding:NSUTF8StringEncoding], YES);
        NSDictionary *bj2 = [self json:bd2.data];
        if (![bj2[@"code"] isEqual:@0]) {
            *err = [NSString stringWithFormat:@"设备绑定失败：%@", PlainMsg(bj2[@"msg"] ?: @"")];
            return nil;
        }
    } else if (![bj[@"code"] isEqual:@0]) {
        *err = [NSString stringWithFormat:@"设备校验失败：%@", PlainMsg(bj[@"msg"] ?: @"")];
        return nil;
    }

    // 6. 常规出入：生成或复用未过期凭证
    GFResp *cr = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/outschool.ashx?flag=autoCreateOutSchoolRecord"],
                      yh, [FormBody(@{@"studentID": sid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *cj = [self json:cr.data];
    if (![cj[@"code"] isEqual:@0]) {
        *err = [NSString stringWithFormat:@"生成凭证失败：%@", cj[@"msg"] ?: @""];
        return nil;
    }
    NSString *oid = cj[@"outSchoolID"] ?: @"";
    if (!oid.length) { *err = @"未返回凭证号"; return nil; }
    self.outSchoolID = oid;

    // 7-9. 打开凭证页 → getPassRecord → getQrcode
    self.outSchoolID = oid;
    // 服务端会根据当前是在校/离校返回 type：出校后再生成，type 会是「入」
    NSString *ty = cj[@"type"];
    if (![ty isKindOfClass:[NSString class]] || !ty.length) ty = @"出";
    NSDictionary *res = [self loadQRForRecord:oid type:ty err:err];
    if (!res) {
        NSString *eo = nil;
        NSString *other = [ty isEqualToString:@"入"] ? @"出" : @"入";
        NSDictionary *r2 = [self loadQRForRecord:oid type:other err:&eo];
        if (r2) { if (err) *err = nil; return r2; }
    }
    return res;
}

- (NSDictionary *)loadQRForRecord:(NSString *)oid type:(NSString *)type err:(NSString **)err {
    BOOL inbound = [type isEqualToString:@"入"];
    NSString *page = [kBase stringByAppendingFormat:@"/ygj2024/outschool/student-outschool.aspx?type=%@&outSchoolID=%@",
                      inbound ? @"%E5%85%A5" : @"%E5%87%BA", oid];
    HTTP(@"GET", page, @{@"User-Agent": kAppUA, @"Referer": [kBase stringByAppendingString:@"/ygj2024/outschool/student-index.aspx"]}, nil, YES);
    GFResp *pr = HTTP(@"POST", [kBase stringByAppendingString:@"/handler/outschool.ashx?flag=getPassRecord"],
                      @{@"User-Agent": kAppUA, @"Origin": kBase, @"Referer": page, @"X-Requested-With": @"XMLHttpRequest"},
                      [FormBody(@{@"studentID": self.studentID ?: @"", @"outSchoolID": oid, @"type": type}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *pj = [self json:pr.data];
    if (![pj[@"code"] isEqual:@0]) {
        if ([pj[@"msg"] containsString:@"outSchoolID"] || [pj[@"msg"] containsString:@"不能为空"])
            *err = @"上一张凭证已被使用或过期，请等 5 分钟后点「生成凭证」";
        else
            *err = [NSString stringWithFormat:@"读取凭证失败：%@", pj[@"msg"] ?: @""];
        return nil;
    }
    NSArray *rows = pj[@"data"];
    NSDictionary *row = [rows isKindOfClass:[NSArray class]] && rows.count ? rows[0] : nil;
    if (!row) { *err = @"凭证不存在"; return nil; }
    NSString *useTime = row[@"useTime"] ?: @"";
    if (useTime.length) {
        *err = [NSString stringWithFormat:@"这张%@校凭证已于 %@ 使用过了", inbound ? @"入" : @"出", useTime];
        return nil;
    }
    GFResp *qr = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/outschool.ashx?flag=getQrcode"],
                      @{@"User-Agent": kAppUA, @"Origin": kBase, @"Referer": page, @"X-Requested-With": @"XMLHttpRequest"},
                      [FormBody(@{@"outSchoolID": oid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *qj = [self json:qr.data];
    if (![qj[@"code"] isEqual:@0] || ![qj[@"qrcode"] isKindOfClass:[NSString class]]) {
        if ([qj[@"msg"] containsString:@"outSchoolID"] || [qj[@"msg"] containsString:@"不能为空"])
            *err = @"上一张凭证已被使用或过期，请等 5 分钟后点「生成凭证」";
        else
            *err = [NSString stringWithFormat:@"二维码获取失败：%@", qj[@"msg"] ?: @""];
        return nil;
    }
    return @{@"qrcode": qj[@"qrcode"], @"row": row, @"outSchoolID": oid, @"type": type};
}

- (void)doOverdue {
    if (self.busy) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"跨天返校"
        message:@"将向学校提交一条「出校超时（申请进校）」，去向：广东省广州市天河区，日期：今天，次数：共一次出入。提交后生成入校凭证。"
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"提交并生成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf runOverdue];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)runOverdue {
    if (self.busy) return;
    self.busy = YES;
    self.statusLabel.text = @"正在提交出校超时（申请进校）…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        NSDictionary *res = [self applyOverdueReturn:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (!res) {
                self.statusLabel.font = [UIFont systemFontOfSize:(err.length > 70 ? 11 : 13)];
                self.statusLabel.text = err.length ? err : @"提交失败";
                return;
            }
            [self applyResult:res];
        });
    });
}

- (NSDictionary *)applyOverdueReturn:(NSString **)err {
    NSString *sid = self.studentID ?: @"";
    if (!sid.length) { *err = @"还没有拿到学号，请先点一次刷新凭证"; return nil; }
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *today = [df stringFromDate:[NSDate date]];
    NSString *addPage = [kBase stringByAppendingString:@"/ygj2024/outschool/student-add.aspx"];
    NSDictionary *h = @{@"User-Agent": kAppUA, @"Origin": kBase, @"Referer": addPage, @"X-Requested-With": @"XMLHttpRequest"};
    HTTP(@"GET", addPage, h, nil, YES);
    NSDictionary *form = @{
        @"outSchoolID": @"0", @"studentID": sid, @"days": @"1",
        @"passNum": @"共一次出入", @"outType": @"CXCS",
        @"outTypeName": @"出校超时（申请进校）",
        @"outAddress": @"广东省广州市天河区",
        @"startDate": today, @"endDate": today,
        @"linkName": @"", @"linkPhone": @"", @"phone": @"",
        @"images": @"", @"picture1": @"", @"picture2": @"",
    };
    GFResp *sr = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/outschool.ashx?flag=save"], h,
                      [FormBody(form) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *sj = [self json:sr.data];
    if (![sj[@"code"] isEqual:@0]) {
        *err = [NSString stringWithFormat:@"提交失败：%@", sj[@"msg"] ?: @""];
        return nil;
    }
    NSString *oid = [sj[@"outSchoolID"] isKindOfClass:[NSString class]] ? sj[@"outSchoolID"] : @"";
    if (!oid.length || [oid isEqualToString:@"0"]) {
        GFResp *mr = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/outschool.ashx?flag=getMyOutSchool"], h,
                          [FormBody(@{@"studentID": sid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
        NSDictionary *mj = [self json:mr.data];
        NSArray *recs = mj[@"data"];
        if (![recs isKindOfClass:[NSArray class]]) recs = @[];
        for (NSDictionary *x in recs) {
            NSString *nm = x[@"outTypeName"] ?: @"";
            NSString *tp = x[@"type"] ?: @"";
            if ([nm containsString:@"超时"] || [tp isEqualToString:@"入"]) {
                oid = x[@"outSchoolID"] ?: @"";
                if (oid.length) break;
            }
        }
        if (!oid.length && recs.count) oid = [recs[0] objectForKey:@"outSchoolID"] ?: @"";
    }
    if (!oid.length) { *err = @"提交成功，但未找到入校凭证，请稍后再点刷新"; return nil; }
    self.outSchoolID = oid;
    return [self loadQRForRecord:oid type:@"入" err:err];
}

- (void)applyResult:(NSDictionary *)res {
    self.qrcodeStr = res[@"qrcode"];
    self.hasQR = YES;
    self.qrView.hidden = NO;
    self.placeholderLabel.hidden = YES;
    [self.refreshBtn setTitle:@"刷新凭证" forState:UIControlStateNormal];
    NSDictionary *row = res[@"row"];
    self.studentName = row[@"studentName"] ?: row[@"name"] ?: @"";
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyy/MM/dd HH:mm:ss";
    df.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSString *st = [row[@"startTime"] ?: row[@"startDate"] ?: @"" stringByReplacingOccurrencesOfString:@"-" withString:@"/"];
    NSString *et = [row[@"endTime"] ?: row[@"endDate"] ?: @"" stringByReplacingOccurrencesOfString:@"-" withString:@"/"];
    self.startDate = [df dateFromString:st];
    self.endDate = [df dateFromString:et];

    NSString *day = self.startDate ? [self dayString:self.startDate] : @"";
    NSString *recordType = res[@"type"] ?: row[@"type"] ?: @"出";
    BOOL inbound = [recordType isEqualToString:@"入"];
    self.titleLabel.text = inbound ? @"入校凭证" : @"出校凭证";
    self.nameLabel.text = [NSString stringWithFormat:@"%@（%@）同学可于 %@ %@校", self.studentName, self.studentID ?: @"", day, inbound ? @"入" : @"出"];
    [self redrawQR];
    self.statusLabel.text = [NSString stringWithFormat:@"凭证 %@ 生成，每 60 秒自动刷新", [self timeString:[NSDate date]]];

    [self.tickTimer invalidate];
    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(onTick) userInfo:nil repeats:YES];
    [self.qrTimer invalidate];
    self.qrTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(onQRTimer) userInfo:nil repeats:YES];
    [self onTick];
}

- (void)onTick {
    if (!self.endDate) {
        self.countdownLabel.text = @"";
        return;
    }
    NSTimeInterval left = [self.endDate timeIntervalSinceNow];
    if (left <= 0) {
        [self.tickTimer invalidate];
        self.countdownLabel.text = @"该凭证已失效，正在重新生成…";
        [self refreshAll];
        return;
    }
    int sec = (int)left;
    self.countdownLabel.text = [NSString stringWithFormat:@"该凭证 %02d:%02d 后将失效，请尽快%@校", sec / 60, sec % 60, [self.titleLabel.text isEqualToString:@"入校凭证"] ? @"入" : @"出"];
}

- (void)onQRTimer {
    if (!self.outSchoolID.length || self.busy) return;
    NSString *oid = self.outSchoolID;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        GFResp *r = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/outschool.ashx?flag=getQrcode"],
                         @{@"User-Agent": kAppUA, @"Origin": kBase, @"Referer": [kBase stringByAppendingFormat:@"/ygj2024/outschool/student-outschool.aspx?outSchoolID=%@", oid], @"X-Requested-With": @"XMLHttpRequest"},
                         [FormBody(@{@"outSchoolID": oid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
        NSDictionary *j = [self json:r.data];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([j[@"code"] isEqual:@0] && [j[@"qrcode"] isKindOfClass:[NSString class]]) {
                self.qrcodeStr = j[@"qrcode"];
                [self redrawQR];
            } else {
                [self refreshAll];
            }
        });
    });
}

- (void)redrawQR {
    if (!self.qrcodeStr.length) return;
    long long ts = (long long)[[NSDate date] timeIntervalSince1970];
    NSString *payload = [self.qrcodeStr stringByAppendingFormat:@"%lld", ts];
    self.qrView.image = [self makeQR:payload size:810];
}

- (UIImage *)makeQR:(NSString *)text size:(CGFloat)size {
    NSData *d = [text dataUsingEncoding:NSISOLatin1StringEncoding];
    CIFilter *f = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [f setValue:d forKey:@"inputMessage"];
    [f setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *img = f.outputImage;
    if (!img) return nil;
    CGFloat scale = size / img.extent.size.width;
    CIImage *scaled = [img imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGImageRef cg = [self.ciContext createCGImage:scaled fromRect:scaled.extent];
    UIImage *u = [UIImage imageWithCGImage:cg scale:3.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return u;
}

#pragma mark - Utils

- (NSDictionary *)json:(NSData *)d {
    if (!d) return @{};
    id o = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [o isKindOfClass:[NSDictionary class]] ? o : @{};
}

- (NSString *)regexGroup:(NSString *)s pattern:(NSString *)p {
    if (!s.length) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:p options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound) return nil;
    return [s substringWithRange:r];
}

- (NSString *)queryValue:(NSString *)query key:(NSString *)key {
    if (!query.length) return nil;
    for (NSString *kv in [query componentsSeparatedByString:@"&"]) {
        NSArray *p = [kv componentsSeparatedByString:@"="];
        if (p.count == 2 && [p[0] isEqualToString:key]) {
            return [p[1] stringByRemovingPercentEncoding] ?: p[1];
        }
    }
    return nil;
}

- (NSString *)dayString:(NSDate *)d {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd";
    f.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    return [f stringFromDate:d];
}

- (NSString *)timeString:(NSDate *)d {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"HH:mm:ss";
    f.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    return [f stringFromDate:d];
}


#pragma mark - 生成凭证 / 签到入口

- (void)showIdle {
    self.hasQR = NO;
    self.titleLabel.text = @"出校码";
    self.qrView.image = nil;
    self.qrView.hidden = YES;
    self.placeholderLabel.hidden = NO;
    self.titleLabel.text = @"出校凭证";
    self.nameLabel.text = @"还没有生成凭证";
    self.countdownLabel.text = @"";
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.text = @"点下方按钮，才会向学校提交一条常规出入申请";
    [self.refreshBtn setTitle:@"生成凭证" forState:UIControlStateNormal];
}

- (void)doOpenSign {
    SignViewController *vc = [SignViewController new];
    vc.host = self;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

#pragma mark - 签到会话（不生成出校凭证）

- (NSString *)prepareSession:(NSString **)err {
    NSString *token = [self savedToken];
    if (!token.length) { if (err) *err = @"NEED_LOGIN"; return nil; }

    NSDictionary *base = @{
        @"User-Agent": kAppUA,
        @"AppVersion": @"5.2.5",
        @"Authorization": [@"Bearer " stringByAppendingString:token],
        @"loginToken": token,
        @"Accept": @"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        @"Accept-Language": @"zh-CN,zh-Hans;q=0.9",
        @"Sec-Fetch-Site": @"none",
        @"Sec-Fetch-Mode": @"navigate",
        @"Sec-Fetch-Dest": @"document",
    };
    NSString *verify = nil;
    GFResp *fr = nil;
    NSArray *cookieModes = @[[self appCookieHeaderWithToken:token overrideToken:NO],
                             [self appCookieHeaderWithToken:token overrideToken:YES]];
    for (NSUInteger i = 0; i < cookieModes.count && !verify.length; i++) {
        if (i) [NSThread sleepForTimeInterval:0.8];
        NSMutableDictionary *h = [base mutableCopy];
        h[@"Cookie"] = cookieModes[i];
        NSString *u1 = @"https://f.yiban.cn/iapp378946";
        GFResp *r1 = HTTP(@"GET", u1, h, nil, NO);
        NSString *loc1 = [self absoluteURL:r1.location base:u1];
        fr = r1;
        GFResp *r2 = nil;
        NSString *finalLoc = loc1 ?: @"";
        if (loc1.length && ![loc1 containsString:@"verify_request="]) {
            r2 = HTTP(@"GET", loc1, h, nil, NO);
            NSString *loc2 = [self absoluteURL:r2.location base:loc1];
            if (loc2.length) finalLoc = loc2;
            fr = r2;
        }
        NSURLComponents *uc = [NSURLComponents componentsWithString:finalLoc];
        for (NSURLQueryItem *it in uc.queryItems) {
            if ([it.name isEqualToString:@"verify_request"]) verify = it.value;
        }
        if (!verify.length) verify = [self regexGroup:finalLoc pattern:@"verify_request=([0-9a-fA-F]{32,})"];
        if (!verify.length) verify = [self regexGroup:(r2 ?: r1).text pattern:@"verify_request=([0-9a-fA-F]{32,})"];
    }
    if (!verify.length) { if (err) *err = @"token 已失效或网络异常，请重新抓一次 token"; return nil; }

    NSString *boundary = @"----WebKitFormBoundaryGDUFQRAPP";
    NSMutableData *mb = [NSMutableData data];
    [mb appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"loginToken\"\r\n\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [mb appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"verify_request\"\r\n\r\n%@\r\n", boundary, verify] dataUsingEncoding:NSUTF8StringEncoding]];
    [mb appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    GFResp *li = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/login.ashx?flag=login"], @{
        @"Content-Type": [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary],
        @"User-Agent": kAppUA,
        @"Origin": kBase,
        @"Referer": fr.finalURL.absoluteString ?: [kBase stringByAppendingString:@"/index.aspx"],
        @"X-Requested-With": @"XMLHttpRequest",
    }, mb, YES);
    NSDictionary *ij = [self json:li.data];
    if (![ij[@"code"] isEqual:@0]) {
        if (err) *err = [NSString stringWithFormat:@"学校登录失败：%@", ij[@"msg"] ?: @""];
        return nil;
    }
    NSString *goTo = ij[@"goToUrl"] ?: @"";
    NSString *sid = [self queryValue:goTo key:@"studentID"] ?: [self regexGroup:goTo pattern:@"studentID=(\\d+)"];
    if (!sid.length) { if (err) *err = @"未获取到学号"; return nil; }
    self.studentID = sid;
    [self setStudentCookie];
    if (goTo.length) {
        NSString *abs = [goTo hasPrefix:@"http"] ? goTo : [kBase stringByAppendingString:([goTo hasPrefix:@"/"] ? goTo : [@"/" stringByAppendingString:goTo])];
        HTTP(@"GET", abs, @{@"User-Agent": kAppUA, @"Referer": fr.finalURL.absoluteString ?: kBase}, nil, YES);
    }

    NSDictionary *yh = @{
        @"User-Agent": kAppUA,
        @"Origin": kBase,
        @"Referer": [kBase stringByAppendingFormat:@"/ygj2024/student-default.aspx?studentID=%@", sid],
        @"X-Requested-With": @"XMLHttpRequest",
    };
    NSString *hid = [kBase stringByAppendingString:@"/Handler/device.ashx?flag="];
    GFResp *nt = HTTP(@"POST", [hid stringByAppendingString:@"getNotice"], yh,
                      [FormBody(@{@"studentID": sid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    if (![[self json:nt.data][@"code"] isEqual:@0]) { if (err) *err = @"初始化会话失败，请点刷新重试"; return nil; }

    NSString *devUUID = kDeviceUUID.length ? kDeviceUUID : [[NSUUID UUID] UUIDString];
    NSString *devModel = @"iPhone 17";
    NSString *devSys = @"27.0";
    NSString *devApp = @"5.2.5";
    GFResp *sd = HTTP(@"POST", [hid stringByAppendingString:@"getStudentDevice"], yh,
                      [FormBody(@{@"studentID": sid}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *sdj = [self json:sd.data];
    if ([sdj[@"code"] isEqual:@0] && [sdj[@"data"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *d in sdj[@"data"]) {
            if (![d isKindOfClass:[NSDictionary class]] || ![d[@"state"] isEqual:@"1"]) continue;
            if ([d[@"uuid"] isKindOfClass:[NSString class]] && [d[@"uuid"] length]) devUUID = d[@"uuid"];
            if ([d[@"deviceModel"] isKindOfClass:[NSString class]] && [d[@"deviceModel"] length]) devModel = d[@"deviceModel"];
            if ([d[@"systemVersion"] isKindOfClass:[NSString class]] && [d[@"systemVersion"] length]) devSys = d[@"systemVersion"];
            if ([d[@"appVersion"] isKindOfClass:[NSString class]] && [d[@"appVersion"] length]) devApp = d[@"appVersion"];
            break;
        }
    }
    NSString *devJson = [NSString stringWithFormat:@"{\"uuid\":\"%@\",\"appVersion\":\"%@\",\"deviceModel\":\"%@\",\"systemVersion\":\"%@\"}",
                         devUUID, devApp, devModel, devSys];
    GFResp *bd = HTTP(@"POST", [hid stringByAppendingString:@"checkBindDevice"], yh,
                      [FormBody(@{@"deviceData": devJson, @"autoBind": @"false"}) dataUsingEncoding:NSUTF8StringEncoding], YES);
    NSDictionary *bj = [self json:bd.data];
    if ([bj[@"code"] isEqual:@1]) {
        NSString *ownJson = [NSString stringWithFormat:@"{\"uuid\":\"%@\",\"appVersion\":\"5.2.5\",\"deviceModel\":\"iPhone\",\"systemVersion\":\"27.0\"}",
                             [[NSUUID UUID] UUIDString]];
        GFResp *bd2 = HTTP(@"POST", [hid stringByAppendingString:@"checkBindDevice"], yh,
                           [FormBody(@{@"deviceData": ownJson, @"autoBind": @"true"}) dataUsingEncoding:NSUTF8StringEncoding], YES);
        if (![[self json:bd2.data][@"code"] isEqual:@0]) {
            if (err) *err = [NSString stringWithFormat:@"设备绑定失败：%@", PlainMsg([self json:bd2.data][@"msg"] ?: @"")];
            return nil;
        }
    } else if (![bj[@"code"] isEqual:@0]) {
        if (err) *err = [NSString stringWithFormat:@"设备校验失败：%@", PlainMsg(bj[@"msg"] ?: @"")];
        return nil;
    }
    return sid;
}

@end


#pragma mark - 签到考勤

@interface GFScannerViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, copy) void (^onCode)(NSString *code);
@end

@implementation GFScannerViewController {
    AVCaptureSession *_session;
    AVCaptureVideoPreviewLayer *_preview;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    UILabel *hint = [UILabel new];
    hint.text = @"把二维码放进画面中央";
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    hint.font = [UIFont systemFontOfSize:14];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [close.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [close.heightAnchor constraintEqualToConstant:36],
        [hint.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-40],
        [hint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [hint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _preview.frame = self.view.bounds;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_session) { [_session startRunning]; return; }
    AVAuthorizationStatus st = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (st == AVAuthorizationStatusDenied || st == AVAuthorizationStatusRestricted) {
        [self alert:@"没有相机权限" msg:@"请到 设置 → 隐私与安全性 → 相机 里允许本 App 使用相机。"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!granted) { [weakSelf alert:@"没有相机权限" msg:@"请到 设置 → 隐私与安全性 → 相机 里允许本 App 使用相机。"]; return; }
            [weakSelf startSession];
        });
    }];
}

- (void)startSession {
    _session = [AVCaptureSession new];
    _session.sessionPreset = AVCaptureSessionPresetHigh;
    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!dev) { [self alert:@"相机不可用" msg:@"没有找到可用的后置相机。"]; return; }
    NSError *e = nil;
    AVCaptureDeviceInput *in = [AVCaptureDeviceInput deviceInputWithDevice:dev error:&e];
    if (!in) { [self alert:@"相机打开失败" msg:e.localizedDescription ?: @"请重试"]; return; }
    if ([_session canAddInput:in]) [_session addInput:in];
    AVCaptureMetadataOutput *out = [AVCaptureMetadataOutput new];
    if ([_session canAddOutput:out]) {
        [_session addOutput:out];
        [out setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        out.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    }
    _preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _preview.frame = self.view.bounds;
    [self.view.layer insertSublayer:_preview atIndex:0];
    [_session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataObject *o in metadataObjects) {
        if (![o isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) continue;
        AVMetadataMachineReadableCodeObject *m = (AVMetadataMachineReadableCodeObject *)o;
        if (![m.type isEqualToString:AVMetadataObjectTypeQRCode]) continue;
        NSString *code = m.stringValue;
        if (!code.length) continue;
        [_session stopRunning];
        void (^cb)(NSString *) = self.onCode;
        [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(code); }];
        return;
    }
}

- (void)closeTapped {
    [_session stopRunning];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

static NSDictionary *GFJSON(NSData *d) {
    if (!d) return @{};
    id o = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [o isKindOfClass:[NSDictionary class]] ? o : @{};
}

static int GFGrade(NSString *yearIn) {
    int y = [yearIn intValue];
    if (y < 2000) y = 2025;
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:[NSDate date]];
    return (int)(c.month >= 9 ? c.year - y + 1 : c.year - y);
}

static int GFWeekNum(NSString *firstWeekDate) {
    NSString *s = [firstWeekDate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    df.dateFormat = @"yyyy/M/d H:mm:ss";
    NSDate *d = [df dateFromString:s];
    if (!d) return 1;
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDate *day0 = [cal startOfDayForDate:d];
    NSInteger dow = [cal component:NSCalendarUnitWeekday fromDate:day0];
    NSInteger shift = (dow == 1) ? -6 : (2 - dow);
    NSDate *monday = [cal dateByAddingUnit:NSCalendarUnitDay value:shift toDate:day0 options:0];
    NSDate *today0 = [cal startOfDayForDate:[NSDate date]];
    NSInteger days = [[cal components:NSCalendarUnitDay fromDate:monday toDate:today0 options:0] day];
    int w = (int)ceil((days + 1) / 7.0);
    return w < 1 ? 1 : w;
}

static NSString *GFHHMMPlus(int minutes) {
    NSDate *d = [NSDate dateWithTimeIntervalSinceNow:minutes * 60.0];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    df.dateFormat = @"HH:mm";
    return [df stringFromDate:d];
}

@implementation SignViewController {
    UILabel *_status;
    UILabel *_courseTitle;
    UILabel *_courseBody;
    UILabel *_hint;
    UIButton *_scanBtn;
    NSString *_sid;
    BOOL _loading;
    BOOL _hasCourse;
    BOOL _signed;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.47 green:0.72 blue:0.26 alpha:1.0];
    UIColor *barColor = [UIColor colorWithRed:0.42 green:0.65 blue:0.23 alpha:1.0];
    UIView *bar = [UIView new];
    bar.backgroundColor = barColor;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:@"‹ 返回" forState:UIControlStateNormal];
    [back setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:16];
    [back addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    back.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:back];

    UILabel *title = [UILabel new];
    title.text = @"签到考勤";
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:title];

    UIButton *reload = [UIButton buttonWithType:UIButtonTypeSystem];
    [reload setTitle:@"刷新" forState:UIControlStateNormal];
    [reload setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    reload.titleLabel.font = [UIFont systemFontOfSize:15];
    [reload addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];
    reload.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:reload];

    _status = [UILabel new];
    _status.text = @"正在登录易广金…";
    _status.font = [UIFont systemFontOfSize:13];
    _status.textColor = [UIColor colorWithWhite:1 alpha:0.9];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_status];

    UIView *card = [UIView new];
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 16;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    _courseTitle = [UILabel new];
    _courseTitle.text = @"正在检测课程…";
    _courseTitle.font = [UIFont boldSystemFontOfSize:19];
    _courseTitle.textColor = [UIColor colorWithWhite:0.13 alpha:1];
    _courseTitle.textAlignment = NSTextAlignmentCenter;
    _courseTitle.numberOfLines = 0;
    _courseTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_courseTitle];

    _courseBody = [UILabel new];
    _courseBody.text = @"";
    _courseBody.font = [UIFont systemFontOfSize:14];
    _courseBody.textColor = [UIColor colorWithWhite:0.33 alpha:1];
    _courseBody.textAlignment = NSTextAlignmentCenter;
    _courseBody.numberOfLines = 0;
    _courseBody.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_courseBody];

    _scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_scanBtn setTitle:@"扫码签到" forState:UIControlStateNormal];
    [_scanBtn setTitleColor:[UIColor colorWithRed:0.18 green:0.49 blue:0.20 alpha:1] forState:UIControlStateNormal];
    _scanBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    _scanBtn.backgroundColor = UIColor.whiteColor;
    _scanBtn.layer.cornerRadius = 24;
    [_scanBtn addTarget:self action:@selector(startScan) forControlEvents:UIControlEventTouchUpInside];
    _scanBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scanBtn];

    _hint = [UILabel new];
    _hint.font = [UIFont systemFontOfSize:12];
    _hint.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 0;
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_hint];

    UIButton *test = [UIButton buttonWithType:UIButtonTypeSystem];
    [test setTitle:@"测试相机（不会提交）" forState:UIControlStateNormal];
    [test setTitleColor:[UIColor colorWithWhite:1 alpha:0.8] forState:UIControlStateNormal];
    test.titleLabel.font = [UIFont systemFontOfSize:12];
    [test addTarget:self action:@selector(testCamera) forControlEvents:UIControlEventTouchUpInside];
    test.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:test];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:g.topAnchor constant:48],
        [back.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [back.centerYAnchor constraintEqualToAnchor:g.topAnchor constant:24],
        [back.heightAnchor constraintEqualToConstant:40],
        [title.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:back.centerYAnchor],
        [reload.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [reload.centerYAnchor constraintEqualToAnchor:back.centerYAnchor],
        [reload.heightAnchor constraintEqualToConstant:40],
        [_status.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:16],
        [_status.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_status.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [card.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:14],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_courseTitle.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [_courseTitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_courseTitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_courseBody.topAnchor constraintEqualToAnchor:_courseTitle.bottomAnchor constant:10],
        [_courseBody.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_courseBody.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_courseBody.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
        [_scanBtn.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:22],
        [_scanBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_scanBtn.widthAnchor constraintEqualToConstant:230],
        [_scanBtn.heightAnchor constraintEqualToConstant:48],
        [_hint.topAnchor constraintEqualToAnchor:_scanBtn.bottomAnchor constant:14],
        [_hint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [_hint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],
        [test.topAnchor constraintEqualToAnchor:_hint.bottomAnchor constant:20],
        [test.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [test.bottomAnchor constraintLessThanOrEqualToAnchor:g.bottomAnchor constant:-16],
    ]];
    [self load];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)load {
    if (_loading) return;
    _loading = YES;
    _hasCourse = NO;
    _signed = NO;
    _scanBtn.enabled = NO;
    [_scanBtn setTitle:@"扫码签到" forState:UIControlStateNormal];
    _courseTitle.text = @"正在检测课程…";
    _courseBody.text = @"";
    _hint.text = @"";
    _status.text = @"正在登录易广金…";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        SignViewController *s = weakSelf;
        if (!s) return;
        if (!s->_sid.length) s->_sid = [s.host prepareSession:&err];
        if (!s->_sid.length) {
            [s finishError:(err.length ? err : @"登录失败")];
            return;
        }
        NSString *u = [kBase stringByAppendingFormat:@"/Handler/sign.ashx?flag=getStuInfoSchedule&studentID=%@", s->_sid];
        GFResp *r = HTTP(@"GET", u, @{@"User-Agent": kAppUA, @"X-Requested-With": @"XMLHttpRequest"}, nil, YES);
        NSDictionary *j = GFJSON(r.data);
        if (![j[@"code"] isEqual:@0]) { [s finishError:[NSString stringWithFormat:@"获取课表失败：%@", j[@"msg"] ?: @""]]; return; }
        NSDictionary *d = j[@"data"];
        if (![d isKindOfClass:[NSDictionary class]]) { [s finishError:@"课表数据异常"]; return; }
        NSString *yearIn = d[@"yearIn"] ?: @"2025";
        NSString *school = d[@"school"] ?: @"清远校区";
        int startSignMin = [d[@"startSignMin"] intValue] ?: 10;
        int week = GFWeekNum(d[@"firstWeekDate"] ?: @"");
        int g = GFGrade(yearIn);
        NSString *xn = d[@"xn"] ?: @"";
        NSString *xnxq = d[@"xnxq"] ?: @"";
        NSArray *all = d[@"scheduleInfo"];
        NSMutableArray *mine = [NSMutableArray array];
        if ([all isKindOfClass:[NSArray class]]) {
            for (NSDictionary *it in all) {
                if (![it isKindOfClass:[NSDictionary class]]) continue;
                if (![[NSString stringWithFormat:@"%d", g] isEqualToString:(it[@"grade"] ?: @"")]) continue;
                NSString *ts = @"", *te = @"";
                if ([school isEqualToString:@"广州校本部"]) { ts = it[@"timeS"] ?: @""; te = it[@"timeE"] ?: @""; }
                else if ([school isEqualToString:@"肇庆校区"]) { ts = it[@"zqTimeS"] ?: @""; te = it[@"zqTimeE"] ?: @""; }
                else { ts = it[@"qyTimeS"] ?: @""; te = it[@"qyTimeE"] ?: @""; }
                NSString *jc = [(it[@"lessonTime"] ?: @"") stringByReplacingOccurrencesOfString:@"第" withString:@""];
                jc = [jc stringByReplacingOccurrencesOfString:@"小节" withString:@""];
                if (ts.length && te.length) [mine addObject:@{@"ts": ts, @"te": te, @"jc": jc}];
            }
        }
        NSString *now = GFHHMMPlus(startSignMin);
        NSString *jc = @"-1", *startTime = @"00:00";
        for (NSDictionary *it in mine) {
            if ([now compare:it[@"ts"]] != NSOrderedAscending && [now compare:it[@"te"]] != NSOrderedDescending) {
                jc = it[@"jc"]; startTime = it[@"ts"]; break;
            }
        }
        NSDictionary *form = @{
            @"studentID": s->_sid, @"grade": [NSString stringWithFormat:@"%d", g],
            @"thisWeek": [NSString stringWithFormat:@"%d", week], @"jc": jc,
            @"xn": xn, @"xnxq": xnxq,
            @"startSignMin": [NSString stringWithFormat:@"%d", startSignMin],
            @"stopSignMin": d[@"stopSignMin"] ?: @"15",
            @"lateSignMin": d[@"lateSignMin"] ?: @"2",
            @"startTime": startTime, @"school": school,
        };
        GFResp *cr = HTTP(@"POST", [kBase stringByAppendingString:@"/Handler/sign.ashx?flag=getCurrentCourse"],
                          @{@"User-Agent": kAppUA, @"Origin": kBase,
                            @"Referer": [kBase stringByAppendingString:@"/ygj2024/sign/student-sign.aspx"],
                            @"X-Requested-With": @"XMLHttpRequest"},
                          [FormBody(form) dataUsingEncoding:NSUTF8StringEncoding], YES);
        NSDictionary *cj = GFJSON(cr.data);
        NSArray *rows = cj[@"data"];
        if ([cj[@"code"] isEqual:@0] && [rows isKindOfClass:[NSArray class]] && rows.count) {
            NSDictionary *c = rows[0];
            NSString *body = [NSString stringWithFormat:@"班级：%@\n老师：%@\n节次：第%@节\n时间：%@ ~ %@",
                              c[@"BJMC"] ?: @"", c[@"SKJSMC"] ?: @"", c[@"DDJ"] ?: @"", c[@"startTime"] ?: @"", c[@"endTime"] ?: @""];
            NSString *name = c[@"KCMC"] ?: @"当前课程";
            dispatch_async(dispatch_get_main_queue(), ^{
                s->_loading = NO; s->_hasCourse = YES;
                s->_courseTitle.text = name;
                s->_courseBody.text = body;
                s->_scanBtn.enabled = YES;
                s->_status.text = @"请扫老师屏幕/黑板上的二维码";
                s->_hint.text = @"扫码后会自动提交签到";
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                s->_loading = NO;
                s->_courseTitle.text = @"无需签到考勤！";
                s->_courseBody.text = @"当前没有需要签到的课程。";
                s->_scanBtn.enabled = NO;
                s->_status.text = @"非上课时间";
                s->_hint.text = @"上课时再点右上角刷新";
            });
        }
    });
}

- (void)finishError:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_loading = NO;
        self->_status.text = ([msg isEqualToString:@"NEED_LOGIN"] ? @"token 已失效，请回主界面更换 token" : msg);
        self->_courseTitle.text = @"加载失败";
        self->_courseBody.text = @"";
        self->_hint.text = @"点右上角刷新重试";
    });
}

- (void)startScan {
    if (!_hasCourse || _signed) return;
    GFScannerViewController *sc = [GFScannerViewController new];
    sc.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak typeof(self) weakSelf = self;
    sc.onCode = ^(NSString *code) { [weakSelf submit:code]; };
    [self presentViewController:sc animated:YES completion:nil];
}

- (void)testCamera {
    GFScannerViewController *sc = [GFScannerViewController new];
    sc.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak typeof(self) weakSelf = self;
    sc.onCode = ^(NSString *code) {
        NSString *show = code.length > 300 ? [[code substringToIndex:300] stringByAppendingString:@"…"] : code;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"扫码测试成功" message:show preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [weakSelf presentViewController:a animated:YES completion:nil];
    };
    [self presentViewController:sc animated:YES completion:nil];
}

- (void)submit:(NSString *)raw {
    _status.text = @"正在提交签到…";
    _scanBtn.enabled = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SignViewController *s = weakSelf;
        if (!s) return;
        NSString *code = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange rr = [code rangeOfString:@"qrcode="];
        if (rr.location != NSNotFound) code = [code substringFromIndex:rr.location + rr.length];
        if (code.length <= 32) { [s submitResult:@"二维码内容不正确" ok:NO]; return; }
        NSString *key = [code substringFromIndex:code.length - 32];
        NSString *content = [code substringToIndex:code.length - 32];
        NSDictionary *form = @{@"key": key, @"content": content, @"studentID": s->_sid ?: @"", @"type": @"1"};
        GFResp *r = HTTP(@"POST", [kBase stringByAppendingFormat:@"/Handler/sign.ashx?flag=saveSignNew2&studentID=%@", s->_sid ?: @""],
                         @{@"User-Agent": kAppUA, @"Origin": kBase,
                           @"Referer": [kBase stringByAppendingString:@"/ygj2024/sign/student-sign.aspx"],
                           @"X-Requested-With": @"XMLHttpRequest"},
                         [FormBody(form) dataUsingEncoding:NSUTF8StringEncoding], YES);
        NSDictionary *j = GFJSON(r.data);
        int c = [j[@"code"] intValue];
        if (c == 0 || c == 2) [s submitResult:@"签到成功" ok:YES];
        else [s submitResult:[NSString stringWithFormat:@"签到失败：%@", j[@"msg"] ?: @"请重试"] ok:NO];
    });
}

- (void)submitResult:(NSString *)msg ok:(BOOL)ok {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ok) {
            self->_signed = YES;
            self->_scanBtn.enabled = NO;
            [self->_scanBtn setTitle:@"已完成签到" forState:UIControlStateNormal];
            self->_status.text = msg;
            self->_hint.text = @"";
        } else {
            self->_scanBtn.enabled = YES;
            self->_status.text = msg;
        }
    });
}

@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindowScene *ws = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:ws];
    self.window.frame = ws.coordinateSpace.bounds;
    self.window.rootViewController = [QRViewController new];
    [self.window makeKeyAndVisible];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                             sessionRole:connectingSceneSession.role];
    cfg.delegateClass = [SceneDelegate class];
    return cfg;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
