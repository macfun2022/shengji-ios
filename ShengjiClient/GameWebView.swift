import SwiftUI
import WebKit

/* =========================================================================
 * WKWebView 容器：加载内置 www/index.html，并通过 URL 参数传入主机地址，
 * 复用与 Android 完全相同的 JS 客户端与渲染逻辑。
 * ========================================================================= */
struct GameWebView: UIViewRepresentable {
    let host: String
    let port: Int
    let name: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        load(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func load(_ webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") else {
            // 兼容扁平资源打包
            if let flat = Bundle.main.url(forResource: "index", withExtension: "html") {
                loadUrl(webView, flat)
            }
            return
        }
        loadUrl(webView, url)
    }

    private func loadUrl(_ webView: WKWebView, _ base: URL) {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "name", value: encodedName),
        ]
        if let final = comps?.url {
            webView.loadFileURL(final, allowingReadAccessTo: base.deletingLastPathComponent())
        } else {
            webView.loadFileURL(base, allowingReadAccessTo: base.deletingLastPathComponent())
        }
    }
}
