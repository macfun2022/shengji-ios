import SwiftUI

/* =========================================================================
 * 主界面：输入昵称 → 扫描/选择主机 → 进入牌桌（WKWebView 复用 JS 客户端）
 * iOS 仅作客户端（系统不支持 App 长期监听局域网端口当主机）。
 * ========================================================================= */
struct ContentView: View {
    @StateObject private var discovery = HostDiscovery()
    // 昵称持久化：下次打开自动带上
    @AppStorage("nickname") private var nickname = ""
    @State private var connected: Connected?

    struct Connected: Identifiable {
        let id = UUID()
        let host: String
        let port: Int
        let name: String
    }

    var body: some View {
        ZStack {
            if let c = connected {
                GameWebView(host: c.host, port: c.port, name: c.name)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Button {
                            connected = nil
                            discovery.stop()
                        } label: {
                            Label("退出牌桌", systemImage: "chevron.left")
                                .padding(8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding()
                    }
            } else {
                connectScreen
            }
        }
    }

    private var connectScreen: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.24, blue: 0.18),
                                    Color(red: 0.07, green: 0.34, blue: 0.25)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("升级")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.43))
                Text("单副54张 · 局域网4人")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                TextField("你的昵称", text: $nickname)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .padding(.top, 20)

                Button {
                    discovery.isScanning ? discovery.stop() : discovery.start()
                } label: {
                    HStack {
                        Image(systemName: discovery.isScanning ? "stop.circle" : "wifi")
                        Text(discovery.isScanning ? "重新扫描" : "扫描局域网主机")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.15))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(discovery.hosts) { h in
                            Button {
                                discovery.stop()
                                connected = Connected(host: h.host, port: h.port,
                                                      name: nickname.isEmpty ? "玩家" : nickname)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(h.name).font(.headline).foregroundColor(.white)
                                        Text("\(h.host):\(h.port)").font(.caption).foregroundColor(.white.opacity(0.7))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.43))
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)

                if discovery.isScanning && discovery.hosts.isEmpty {
                    Text("正在扫描… 请确保与主机在同一个 WiFi")
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                } else if !discovery.isScanning && discovery.hosts.isEmpty {
                    Text("点“扫描局域网主机”查找同一 WiFi 下已开主机的手机")
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            // 首次进入触发一次局域网权限弹窗（iOS 需用户授权）
            discovery.start()
        }
    }
}
