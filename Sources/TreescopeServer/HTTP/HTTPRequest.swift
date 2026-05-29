import Foundation

/// A parsed HTTP/1.1 request line + headers. Bodies are not needed by the
/// Treescope routes (everything is GET or a WebSocket upgrade).
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    /// Header names are lowercased for case-insensitive lookup.
    let headers: [String: String]

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var isWebSocketUpgrade: Bool {
        header("upgrade")?.lowercased().contains("websocket") == true
            && header("sec-websocket-key") != nil
    }

    /// Parses the request from a header block (everything before the blank line).
    /// Returns nil if the block is not yet complete / malformed.
    static func parse(headerBlock: String) -> HTTPRequest? {
        var lines = headerBlock.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])

        var path = target
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<q])
            let queryString = String(target[target.index(after: q)...])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
                query[key] = value
            }
        }
        path = path.removingPercentEncoding ?? path

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return HTTPRequest(method: method, path: path, query: query, headers: headers)
    }
}

/// Helpers to build raw HTTP/1.1 responses.
enum HTTPResponse {
    static func make(status: String, contentType: String, body: Data,
                     extraHeaders: [String: String] = [:]) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func ok(_ body: Data, contentType: String) -> Data {
        make(status: "200 OK", contentType: contentType, body: body)
    }

    static func notFound() -> Data {
        make(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("not found".utf8))
    }

    /// The WebSocket upgrade handshake response (101 Switching Protocols).
    static func switchingProtocols(acceptKey: String) -> Data {
        var head = "HTTP/1.1 101 Switching Protocols\r\n"
        head += "Upgrade: websocket\r\n"
        head += "Connection: Upgrade\r\n"
        head += "Sec-WebSocket-Accept: \(acceptKey)\r\n"
        head += "\r\n"
        return Data(head.utf8)
    }
}
