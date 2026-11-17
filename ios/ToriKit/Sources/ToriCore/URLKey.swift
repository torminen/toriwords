/// URL key for Sources with a URL (doc 36 §15.1). Explicit split per code point, never a platform URL
/// parser (they differ in IDN, percent-encoding and port handling):
/// `scheme ':' '//' [userinfo '@'] host [':' port] path ['?' query] ['#' fragment]`.
extension TextKey {
    static let trackingParams: Set<String> = ["fbclid", "gclid", "yclid", "mc_eid"]
    static let defaultPorts = ["http": "80", "https": "443"]

    public static func urlKey(_ url: String) -> String {
        var s = Array(nfc(url).unicodeScalars)[...]
        while let f = s.first, isWhitespace(f) { s.removeFirst() }
        while let l = s.last, isWhitespace(l) { s.removeLast() }
        guard let colon = s.firstIndex(of: ":"), colon > s.startIndex else { return string(s) }
        let scheme = lowercase(string(s[..<colon]))
        let afterColon = s[(colon + 1)...]
        guard let defaultPort = defaultPorts[scheme], afterColon.starts(with: ["/", "/"]) else { return string(s) }
        var rest = afterColon.dropFirst(2)
        if let hash = rest.firstIndex(of: "#") { rest = rest[..<hash] }
        var query: ArraySlice<Unicode.Scalar>?
        if let q = rest.firstIndex(of: "?") {
            query = rest[(q + 1)...]
            rest = rest[..<q]
        }
        var authority = rest, path: ArraySlice<Unicode.Scalar> = []
        if let slash = rest.firstIndex(of: "/") {
            authority = rest[..<slash]
            path = rest[slash...]
        }
        var userinfo: ArraySlice<Unicode.Scalar> = []
        if let at = authority.lastIndex(of: "@") {
            userinfo = authority[...at]
            authority = authority[(at + 1)...]
        }
        var host = authority
        var port: String?
        if host.first != "[", let c = host.lastIndex(of: ":") {
            port = string(host[(c + 1)...])
            host = host[..<c]
        }
        if let p = port, p.unicodeScalars.isEmpty || p.unicodeScalars.elementsEqual(defaultPort.unicodeScalars) { port = nil }
        var out = scheme + "://" + string(userinfo) + punycodeHost(lowercase(string(host)))
        if let port { out += ":" + port }
        out += string(path)
        if let query {
            let kept = query.split(separator: "&", omittingEmptySubsequences: false).filter { param in
                let name = param.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]
                return !(name.starts(with: "utm_".unicodeScalars) || trackingParams.contains(string(name)))
            }
            if !(kept.isEmpty || (kept.count == 1 && kept[0].isEmpty)) {
                out += "?" + kept.map(string).joined(separator: "&")
            }
        }
        return out
    }

    static func punycodeHost(_ host: String) -> String {
        Array(host.unicodeScalars).split(separator: ".", omittingEmptySubsequences: false).map { label in
            label.allSatisfy(\.isASCII) ? string(label) : "xn--" + Punycode.encode(Array(label))
        }.joined(separator: ".")
    }
}
/// RFC 3492 Punycode encoder (only encoding is needed).
enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 0x80

    static func encode(_ input: [Unicode.Scalar]) -> String {
        var output = input.filter(\.isASCII).map(Character.init)
        let basicCount = output.count
        var handled = basicCount
        if basicCount > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        let codes = input.map { Int($0.value) }
        while handled < codes.count {
            let m = codes.filter { $0 >= n }.min()!
            delta += (m - n) * (handled + 1)
            n = m
            for c in codes {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return String(output)
    }

    private static func digit(_ d: Int) -> Character {
        Character(Unicode.Scalar(UInt8(d < 26 ? 0x61 + d : 0x30 + d - 26)))
    }

    private static func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / numPoints
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }
}
