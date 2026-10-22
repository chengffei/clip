import Foundation

/// Cloudflare R2 PUT Object uploader. R2 is S3-compatible, so it reuses AWS
/// Signature V4 — signed with region `auto` against the account endpoint
/// `<accountId>.r2.cloudflarestorage.com` using path-style addressing.
///
/// Required fields: `accessKeyId`, `secretAccessKey`, `accountId`, `bucket`.
/// Optional fields:
///   - `path`      — key prefix, e.g. `screenshots`.
///   - `customUrl` — public domain (R2 custom domain or r2.dev subdomain).
///                   Without it R2 objects are not publicly reachable; the
///                   returned link is the signing endpoint and won't open in a
///                   browser, so configuring a custom domain is recommended.
enum R2Uploader: UploaderProtocol {
    static let kind: UploadProviderKind = .r2

    static func validate(_ config: ProviderConfig) -> String? {
        for key in ["accessKeyId", "secretAccessKey", "accountId", "bucket"] {
            if config.nonEmpty(key) == nil {
                return L10n.missingField(key)
            }
        }
        return nil
    }

    static func upload(
        data: Data,
        fileName: String,
        contentType: String,
        config: ProviderConfig,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if let err = validate(config) {
            completion(.failure(UploadError.invalidConfig(err)))
            return
        }
        let id        = config.value("accessKeyId")
        let secret    = config.value("secretAccessKey")
        let accountId = normalizeAccountId(config.value("accountId"))
        let bucket    = config.value("bucket")
        let key       = S3Common.normalizePrefix(config.nonEmpty("path")) + fileName
        let encodedKey = AWSV4Signer.encodePath(key)

        let host = "\(accountId).r2.cloudflarestorage.com"
        let canonicalURI = "/\(bucket)/\(encodedKey)"

        guard let endpointURL = URL(string: "https://\(host)/\(bucket)/\(encodedKey)") else {
            completion(.failure(UploadError.invalidConfig("bad account id or bucket")))
            return
        }

        var publicURL = endpointURL
        if let custom = config.nonEmpty("customUrl"),
           let u = S3Common.customURL(custom, encodedKey: encodedKey) {
            publicURL = u
        }

        S3Common.put(
            data: data,
            host: host,
            canonicalURI: canonicalURI,
            region: "auto",
            accessKeyId: id,
            secretAccessKey: secret,
            contentType: contentType,
            publicURL: publicURL,
            progress: progress,
            completion: completion
        )
    }

    /// Accepts either a bare Cloudflare account ID or a pasted full endpoint and
    /// returns just the account ID.
    private static func normalizeAccountId(_ raw: String) -> String {
        var s = S3Common.stripScheme(raw)
        if let range = s.range(of: ".r2.cloudflarestorage.com") {
            s = String(s[s.startIndex..<range.lowerBound])
        }
        return s
    }
}
