import UIKit

/// Downloadt de receptfoto op het toestel. Het toestel kan het CDN van een receptsite meestal wél bereiken,
/// ook als de site de server blokkeert. Mislukt het, dan stuurt de extensie alleen de foto-link mee.
enum RecipePhotoDownloader {
    static let maxBytes = 8 * 1024 * 1024
    static let timeout: TimeInterval = 10

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        return URLSession(configuration: config)
    }()

    /// JPEG en PNG gaan ongewijzigd mee; andere formaten (WebP, AVIF, HEIC) worden JPEG, want die kan de server altijd lezen.
    static func download(_ urlString: String, referer: String) async -> API.UploadFile? {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
        if !referer.isEmpty { request.setValue(referer, forHTTPHeaderField: "Referer") }
        do {
            // De time-out van 10 s begrenst ook hoeveel er binnenkomt als de server geen lengte meldt.
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let mime = http.mimeType?.lowercased(), mime.hasPrefix("image/"),
                  !data.isEmpty, data.count <= maxBytes else { return nil }
            switch mime {
            case "image/jpeg", "image/jpg", "image/pjpeg":
                return API.UploadFile(data: data, filename: "foto.jpg", mimeType: "image/jpeg")
            case "image/png":
                return API.UploadFile(data: data, filename: "foto.png", mimeType: "image/png")
            default:
                guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) else { return nil }
                return API.UploadFile(data: jpeg, filename: "foto.jpg", mimeType: "image/jpeg")
            }
        } catch {
            return nil
        }
    }
}
