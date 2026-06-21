import Foundation
import UIKit

extension APIDataService {
    // MARK: - Care Log
    func fetchCareLogEntries(date: Date?) async throws -> [CareLogEntry] {
        if let date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = formatter.string(from: date)
            return try await get(path: APIEndpoint.careLogs(on: dateStr))
        }
        return try await get(path: APIEndpoint.careLogs)
    }

    func uploadCareLogPhoto(_ image: UIImage) async throws -> CareLogPhotoUploadReference {
        struct UploadURLResponse: Codable {
            let uploadUrl: String
            let photoKey: String
        }

        let contentType = "image/jpeg"
        let uploadInfo: UploadURLResponse = try await post(
            path: APIEndpoint.careLogUploadURL,
            body: ["content_type": contentType]
        )

        guard let jpegData = image.careLogUploadData(),
              let uploadURL = URL(string: uploadInfo.uploadUrl) else {
            throw APIError.emptyResponse
        }
        let sanitizedData = try privacyRedactionService.stripMetadata(
            from: jpegData,
            mimeType: contentType
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 20
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.upload(
                for: request,
                from: sanitizedData
            )
        } catch let error as URLError where [
            .timedOut,
            .cannotConnectToHost,
            .cannotFindHost,
            .networkConnectionLost,
            .notConnectedToInternet,
        ].contains(error.code) {
            throw CareLogPhotoUploadError.storageUnavailable
        }
        guard let http = response as? HTTPURLResponse,
              200...299 ~= http.statusCode else {
            throw APIError.serverError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }

        return CareLogPhotoUploadReference(photoKey: uploadInfo.photoKey)
    }

    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry { try await post(path: APIEndpoint.careLogs, body: entry) }
}

private enum CareLogPhotoUploadError: LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        "照片儲存服務目前無法連線，請確認網路後再試。"
    }
}

private extension UIImage {
    func careLogUploadData(maxDimension: CGFloat = 2048) -> Data? {
        let longestSide = max(size.width, size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}
