# iOS 客户端（升级 · 局域网）

> ⚠️ **重要说明**：iOS 不允许 App 在后台长期监听局域网端口当"主机"，
> 所以 **iOS 端只能做客户端**（主机角色请用 Android 手机）。
> 另外，**iOS 工程必须在 macOS + Xcode 上编译**，Windows 无法产出 .ipa。

## 它的作用
- 与 Android 端相同的牌桌 UI（复用同一套 JS 客户端：`ShengjiClient/www/`）。
- 用 **Bonjour/mDNS**（服务类型 `_shengji._tcp`）自动发现同一 WiFi 下的 Android 主机，
  点击即加入，体验类似"连接 Wi-Fi"。

## 在 Mac 上构建（二选一）

### 方式 A：XcodeGen（推荐，最省事）
```bash
brew install xcodegen          # 若未安装
cd ios
xcodegen generate              # 生成 ShengjiClient.xcodeproj
open ShengjiClient.xcodeproj   # 打开后选真机运行
```

### 方式 B：一键命令行出 ipa（脚本已备好）
```bash
brew install xcodegen          # 若未安装
cd ios
# ① 先编辑 build-ipa.sh，把 TEAM_ID="YOUR_TEAM_ID" 改成你的 Team ID
bash build-ipa.sh
# ② 产物：dist/ShengjiClient.ipa
```

**Team ID 怎么找**：
- 最简单：`security find-identity -v -p codesigning`（输出括号内的一串），
  或登录 [developer.apple.com](https://developer.apple.com/account) → Membership details → Team ID。
- **免费 Apple ID 也行**：Xcode 里 Settings → Accounts 登录一次 Apple ID 并建好证书后，
  再跑脚本（method=development）。缺点：签名 7 天过期，到期需重装。
- **付费开发者账号（$99/年）**：把 `ExportOptions-dev.plist` 的 `method` 改为 `ad-hoc`
  可做正式分发，签名 1 年有效。

**ipa 安装到 iPhone（任选其一）**：
1. **Xcode**：USB 连手机 → Window → Devices and Simulators → 把 ipa 拖进 Installed Apps。
2. **Apple Configurator 2**（Mac App Store 免费）：同样 USB 拖入。
3. **Sideloadly / AltStore**：适合不用数据线的场景（AltStore 需同 WiFi）。

### 方式 C：手动新建工程
1. Xcode → New Project → iOS App，Product Name 填 `ShengjiClient`，
   Interface 选 **SwiftUI**，Language 选 **Swift**。
2. 把 `ShengjiClient/` 下的 `*.swift`、`Info.plist` 拖入工程。
3. 把 `ShengjiClient/www/` 整个**文件夹**拖入工程，选择
   **Create folder references**（蓝色文件夹），确保打包后仍是 `www/` 子目录。
4. 在 Target → Signing & Capabilities 里配置你的开发者团队。
5. 真机运行（局域网权限会弹窗，允许即可）。

## 关键配置（已在 Info.plist 中写好）
- `NSLocalNetworkUsageDescription`：局域网权限弹窗文案（必需）。
- `NSBonjourServices = ["_shengji._tcp"]`：声明要浏览的 Bonjour 服务（必需，否则发现不到）。
- `NSAppTransportSecurity`：允许局域网明文 `ws://`。

## 与 Android 主机的配合
1. Android 手机 A 打开 App → 点「创建主机」→ 前台服务启动 WebSocket 服务器 + 广播 `_shengji._tcp`。
2. iOS 手机打开 App → 自动扫描 → 列表出现"升级主机-XXX" → 点击加入。
3. 满 4 人自动开局。

## 目录结构
```
ios/
  project.yml                      XcodeGen 配置
  README-iOS.md                    本说明
  ShengjiClient/
    ShengjiClient.xcodeproj/       工程（可选，用 xcodegen 可重新生成）
    ShengjiClient/
      ShengjiApp.swift             App 入口
      ContentView.swift            主界面（扫描 + 选择主机）
      HostDiscovery.swift          Bonjour/mDNS 发现
      GameWebView.swift            WKWebView 容器
      Info.plist                   权限与服务声明
      www/                         复用的 JS 客户端（index.html/app.js/game.js/style.css）
```
