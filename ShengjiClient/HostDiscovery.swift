import Foundation

/* =========================================================================
 * mDNS / Bonjour 发现：浏览 _shengji._tcp 服务，解析出可用主机。
 * 需在 Info.plist 配置 NSLocalNetworkUsageDescription 与 NSBonjourServices。
 * ========================================================================= */
final class HostDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {

    struct Host: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int
    }

    @Published var hosts: [Host] = []
    @Published var isScanning = false

    private var browser: NetServiceBrowser?
    private var pending: [NetService] = []

    static let serviceType = "_shengji._tcp."

    func start() {
        guard browser == nil else { return }
        hosts.removeAll()
        isScanning = true
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: HostDiscovery.serviceType, inDomain: "local.")
        browser = b
    }

    func stop() {
        browser?.stop()
        browser = nil
        pending.removeAll()
        isScanning = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // 为避免只解析到 IPv6/本地回环，这里逐个 resolve
        pending.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        hosts.removeAll { $0.name == service.name }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let (ip, port) = extract(sender)
        guard let ip = ip else { return }
        if ip == "127.0.0.1" { return }
        let h = Host(name: sender.name, host: ip, port: port)
        DispatchQueue.main.async {
            if !self.hosts.contains(where: { $0.name == h.name && $0.host == h.host }) {
                self.hosts.append(h)
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // ignore
    }

    /// 从 NetService 的地址中提取 IPv4 字符串与端口
    private func extract(_ service: NetService) -> (String?, Int) {
        let port = service.port
        guard let addresses = service.addresses else { return (service.hostName, port) }
        for data in addresses {
            let ip = ipString(from: data)
            if let ip = ip, isIPv4(ip) { return (ip, port) }
        }
        // 退而求其次：返回 hostName（去掉末尾的 .）
        if let hn = service.hostName {
            return (hn.hasSuffix(".") ? String(hn.dropLast()) : hn, port)
        }
        return (nil, port)
    }

    private func ipString(from data: Data) -> String? {
        var storage = sockaddr_storage()
        (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
        if Int32(storage.ss_family) == AF_INET {
            var addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sin = addr.sin_addr
            inet_ntop(AF_INET, &sin, &buffer, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buffer)
        }
        return nil
    }

    private func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}
