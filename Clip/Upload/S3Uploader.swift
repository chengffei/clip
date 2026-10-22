import Foundation

/// Amazon S3 (and S3-compatible endpoints) PUT Object uploader, signed with
/// AWS Signature V4.
///
/// Required fields: `accessKeyId`, `secretAccessKey`, `bucket`, `region`.
/// Optional fields:
///   - `endpoint`  — host of an S3-compatible service (MinIO, Backblaze B2, …).
///                   When set, path-style addressing is used; when empty, the
///                   AWS virtual-hosted host `<bucket>.s3.<region>.amazonaws.com`.
///   - `path`      — key prefix, e.g. `screenshots`.
///   - `customUrl` — custom CDN domain for the returned link.
enum S3Uploader: UploaderProtocol {
    static let kind: UploadProviderKind = .s3

    static func validate(_ config: ProviderConfig) -> String? {
        for key in ["accessKeyId", "secretAccessKey", "bucket", "region"] {
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
        let id     = config.value("accessKeyId")
        let secret = config.value("secretAccessKey")
        let bucket = config.value("bucket")
        let region = config.value("region")
        let key    = S3Common.normalizePrefix(config.nonEmpty("path")) + fileName
        let encodedKey = AWSV4Signer.encodePath(key)

        let host: String
        let canonicalURI: String
        let defaultURL: URL

        if let endpoint = config.nonEmpty("endpoint") {
            // S3-compatible endpoint → path-style addressing.
            host = S3Common.stripScheme(endpoint)
            canonicalURI = "/\(bucket)/\(encodedKey)"
            guard let u = URL(string: "https://\(host)/\(bucket)/\(encodedKey)") else {
                completion(.failure(UploadError.invalidConfig("bad endpoint")))
                return
            }
            defaultURL = u
        } else {
            // Amazon S3 → virtual-hosted-style addressing.
            host = "\(bucket).s3.\(region).amazonaws.com"
            canonicalURI = "/\(encodedKey)"
            guard let u = URL(string: "https://\(host)/\(encodedKey)") else {
                completion(.failure(UploadError.invalidConfig("bad bucket or region")))
                return
            }
            defaultURL = u
        }

        var publicURL = defaultURL
        if let custom = config.nonEmpty("customUrl"),
           let u = S3Common.customURL(custom, encodedKey: encodedKey) {
            publicURL = u
        }

        S3Common.put(
            data: data,
            host: host,
            canonicalURI: canonicalURI,
            region: region,
            accessKeyId: id,
            secretAccessKey: secret,
            contentType: contentType,
            publicURL: publicURL,
            progress: progress,
            completion: completion
        )
    }
}
