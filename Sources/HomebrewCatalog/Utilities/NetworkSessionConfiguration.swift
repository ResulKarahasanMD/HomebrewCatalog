import Foundation

enum NetworkSessionConfiguration {
    /// Builds a URL session configuration for HTTPS API clients.
    ///
    /// Uses an explicit proxy dictionary so Network/CFNetwork does not evaluate a broken
    /// system PAC file (``nw_proxy_resolver_create_parsed_array`` / ``kCFNetworkAgentXPCMessageTypePACQuery``).
    /// Manual HTTP/HTTPS/SOCKS proxies from System Settings are preserved when enabled.
    static func apiClient(
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval? = nil,
        waitsForConnectivity: Bool = false
    ) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        if let resourceTimeout {
            config.timeoutIntervalForResource = resourceTimeout
        }
        config.waitsForConnectivity = waitsForConnectivity
        config.connectionProxyDictionary = connectionProxyDictionary()
        return config
    }

    private static func connectionProxyDictionary() -> [String: Any] {
        var dict = directConnectionDictionary()
        guard let system = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return dict
        }
        for key in Self.manualProxyKeys {
            if let value = system[key] {
                dict[key] = value
            }
        }
        return dict
    }

    private static let manualProxyKeys = [
        "HTTPEnable",
        "HTTPProxy",
        "HTTPPort",
        "HTTPSEnable",
        "HTTPSProxy",
        "HTTPSPort",
        "SOCKSEnable",
        "SOCKSProxy",
        "SOCKSPort",
        "ExceptionsList",
    ]

    private static func directConnectionDictionary() -> [String: Any] {
        [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesProxyAutoConfigEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
        ]
    }
}
