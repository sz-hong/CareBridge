import Foundation

protocol APIHTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: APIHTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

struct APIClient {
    private let baseURL: String
    private let session: APIHTTPSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: String,
        session: APIHTTPSession = URLSession.shared,
        decoder: JSONDecoder = APIClient.makeDecoder(),
        encoder: JSONEncoder = APIClient.makeEncoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    func request<T: Codable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        authToken: String? = nil
    ) async throws -> T {
        guard let url = makeURL(method: method, path: path) else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        configureCachePolicy(for: &req, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let authToken {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(statusCode: 0)
        }

        guard 200...299 ~= http.statusCode else {
            if let parsed = try? decoder.decode(ErrorEnvelope.self, from: data),
               let message = parsed.error?.message,
               !message.isEmpty {
                throw APIError.backendError(statusCode: http.statusCode, message: message)
            }
            throw APIError.serverError(statusCode: http.statusCode)
        }

        if data.isEmpty || http.statusCode == 204 {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            throw APIError.emptyResponse
        }

        let apiResponse: APIResponse<T>
        do {
            apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print(
                "[APIClient] decode failed for \(T.self): "
                + "\(String(reflecting: error))\n"
                + "[APIClient] response body: \(responseBody.prefix(4_000))"
            )
            #endif
            throw error
        }
        guard let result = apiResponse.data else {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            throw APIError.emptyResponse
        }
        return result
    }

    func requestPage<T: Codable>(
        _ method: String,
        path: String,
        authToken: String? = nil
    ) async throws -> PaginatedResult<T> {
        guard let url = makeURL(method: method, path: path) else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        configureCachePolicy(for: &req, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let authToken {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(statusCode: 0)
        }

        guard 200...299 ~= http.statusCode else {
            if let parsed = try? decoder.decode(ErrorEnvelope.self, from: data),
               let message = parsed.error?.message,
               !message.isEmpty {
                throw APIError.backendError(
                    statusCode: http.statusCode,
                    message: message
                )
            }
            throw APIError.serverError(statusCode: http.statusCode)
        }

        let apiResponse = try decoder.decode(APIResponse<[T]>.self, from: data)
        let items = apiResponse.data ?? []
        return PaginatedResult(
            items: items,
            totalCount: apiResponse.meta?.count ?? items.count,
            hasNextPage: apiResponse.meta?.next != nil
        )
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private func configureCachePolicy(for request: inout URLRequest, method: String) {
        guard method.uppercased() == "GET" else { return }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
    }

    private func makeURL(method: String, path: String) -> URL? {
        let rawURL = "\(baseURL)\(path)"
        guard method.uppercased() == "GET",
              var components = URLComponents(string: rawURL) else {
            return URL(string: rawURL)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(
            URLQueryItem(
                name: "_cb",
                value: String(Int(Date().timeIntervalSince1970 * 1000))
            )
        )
        components.queryItems = queryItems
        return components.url
    }
}

private struct ErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable {
        let message: String?
    }

    let error: ErrorDetail?
}

struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeValue = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
