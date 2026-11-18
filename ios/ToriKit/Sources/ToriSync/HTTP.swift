import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One API request relative to the base URL `https://<api-host>/v1` (doc 36 §19.1).
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    /// Path below the base URL, e.g. `/sync/push`.
    public var path: String
    public var query: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, path: String, query: [URLQueryItem] = [], headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    /// Header names lowercased.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.body = body
    }
}

/// The network seam: URLSession in the app, an in-memory hub in tests.
public protocol HTTPTransport: Sendable {
    /// Throws `TransportError` when no response arrived.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public enum TransportError: Error, Equatable, Sendable {
    /// No network path (`NWPathMonitor` unsatisfied / URLError.notConnectedToInternet).
    case offline
    /// A path exists but the server did not answer (timeout, DNS, TLS, connection refused).
    case unreachable
}

/// URLSession-backed transport. Gzip request bodies are sent where `Compression` exists (Apple platforms).
public struct URLSessionTransport: HTTPTransport {
    public let baseURL: URL
    let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent(request.path), resolvingAgainstBaseURL: false)!
        if !request.query.isEmpty { components.queryItems = request.query }
        var r = URLRequest(url: components.url!, timeoutInterval: 60)
        r.httpMethod = request.method
        for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
        if let body = request.body {
            if let gz = Gzip.compress(body) {
                r.httpBody = gz
                r.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            } else {
                r.httpBody = body
            }
        }
        do {
            let (data, response) = try await session.data(for: r)
            guard let http = response as? HTTPURLResponse else { throw TransportError.unreachable }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields { headers["\(k)".lowercased()] = "\(v)" }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: throw TransportError.offline
            default: throw TransportError.unreachable
            }
        }
    }
}

/// RFC 1952 gzip around a raw DEFLATE stream from Apple's `Compression` (zlib = raw deflate there).
enum Gzip {
    static func compress(_ data: Data) -> Data? {
        #if canImport(Compression)
        guard let deflated = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }
        var out = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
        out.append(deflated)
        appendLE(&out, crc32(data))
        appendLE(&out, UInt32(truncatingIfNeeded: data.count))
        return out
        #else
        return nil
        #endif
    }

    static func appendLE(_ out: inout Data, _ v: UInt32) {
        out.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)])
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
