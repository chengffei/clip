import Foundation

/// AWS Signature V4 request signing for S3-compatible PUT Object uploads.
/// Shared by `S3Uploader` (Amazon S3) and `R2Uploader` (Cloudflare R2 — which is
/// S3-compatible and signs with region `auto`).
enum AWSV4Signer {
    /// Percent-encodes an object key for a canonical URI: each `/`-separated
    /// segment is encoded against the RFC 3986 unreserved set, slashes preserved.
    static func encodePath(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).cosURLEncoded() }
            .joined(separator: "/")
    }

    /// Builds a fully signed PUT Object request.
    /// - Parameters:
    ///   - host: request host — also the `Host` header and TLS SNI.
    ///   - canonicalURI: percent-encoded request path, with a leading `/`.
    ///   - region: SigV4 region — e.g. `us-east-1`, or `auto` for R2.
    ///   - accessKeyId/secretAccessKey: credentials.
    ///   - payload: the object bytes to upload.
    ///   - contentType: MIME type, e.g. `image/png`.
    /// - Returns: a signed `URLRequest`, or nil if the URL could not be formed.
    static func signedPutRequest(
        host: String,
        canonicalURI: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        payload: Data,
        contentType: String,
        now: Date = Date()
    ) -> URLRequest? {
        guard let url = URL(string: "https://\(host)\(canonicalURI)") else { return nil }

        let service = "s3"
        let (amzDate, dateStamp) = timestamps(now)
        let payloadHash = UploadCrypto.sha256Hex(payload)

        // --- Canonical request (headers must be sorted by lowercased name) ---
        let canonicalHeaders =
            "content-type:\(contentType)\n" +
            "host:\(host)\n" +
            "x-amz-content-sha256:\(payloadHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = [
            "PUT",
            canonicalURI,
            "",                 // empty canonical query string
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        // --- String to sign ---
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            UploadCrypto.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        // --- Derive signing key + signature ---
        let kDate = UploadCrypto.hmacSHA256(key: Data("AWS4\(secretAccessKey)".utf8),
                                            message: Data(dateStamp.utf8))
        let kRegion = UploadCrypto.hmacSHA256(key: kDate, message: Data(region.utf8))
        let kService = UploadCrypto.hmacSHA256(key: kRegion, message: Data(service.utf8))
        let kSigning = UploadCrypto.hmacSHA256(key: kService, message: Data("aws4_request".utf8))
        let signature = UploadCrypto.hex(
            UploadCrypto.hmacSHA256(key: kSigning, message: Data(stringToSign.utf8))
        )

        let authorization = "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKeyId)/\(scope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(host, forHTTPHeaderField: "Host")
        req.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        req.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-Sha256")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("\(payload.count)", forHTTPHeaderField: "Content-Length")
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        return req
    }

    /// AWS timestamp pair: `yyyyMMdd'T'HHmmss'Z'` and `yyyyMMdd`, both in GMT.
    private static func timestamps(_ date: Date) -> (amz: String, stamp: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amz = f.string(from: date)
        f.dateFormat = "yyyyMMdd"
        let stamp = f.string(from: date)
        return (amz, stamp)
    }
}

/// Shared helpers for the S3 / R2 uploaders: key-prefix normalization, endpoint
/// cleanup, custom-domain URL assembly, and the signed PUT transport.
enum S3Common {
    /// Normalizes an optional path prefix to either "" or "trimmed/".
    static func normalizePrefix(_ raw: String?) -> String {
        guard var p = raw, !p.isEmpty else { return "" }
        while p.hasPrefix("/") { p.removeFirst() }
        while p.hasSuffix("/") { p.removeLast() }
        return p.isEmpty ? "" : p + "/"
    }

    /// Strips scheme + trailing slashes from a host/endpoint string.
    static func stripScheme(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("https://") { s.removeFirst(8) }
        if s.hasPrefix("http://")  { s.removeFirst(7) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Joins a user-supplied custom domain with the encoded object key.
    static func customURL(_ custom: String, encodedKey: String) -> URL? {
        var base = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/\(encodedKey)")
    }

    /// Signs and PUTs `data` to an S3-style location, reporting `publicURL` on success.
    static func put(
        data: Data,
        host: String,
        canonicalURI: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        contentType: String,
        publicURL: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let req = AWSV4Signer.signedPutRequest(
            host: host,
            canonicalURI: canonicalURI,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            payload: data,
            contentType: contentType
        ) else {
            completion(.failure(UploadError.invalidConfig("bad endpoint")))
            return
        }

        let client = UploadHTTPClient()
        client.upload(request: req, body: data, progress: progress) { result in
            withExtendedLifetime(client) {
                switch result {
                case .failure(let err):
                    completion(.failure(err))
                case .success(let (body, response)):
                    if (200..<300).contains(response.statusCode) {
                        completion(.success(publicURL))
                    } else {
                        let msg = String(data: body, encoding: .utf8) ?? "HTTP \(response.statusCode)"
                        completion(.failure(UploadError.server(response.statusCode, msg)))
                    }
                }
            }
        }
    }
}
