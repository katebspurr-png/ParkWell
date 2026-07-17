import Foundation
import UIKit

/// Camera-fallback: sends a photo of an ambiguous/unmapped sign to the
/// `interpret-sign` Supabase Edge Function, which calls a vision LLM and
/// returns a structured plain-English verdict.
///
/// The API key for the LLM lives server-side in the edge function — the app
/// only ever holds the Supabase anon key.
struct SignVisionService {
    struct SignVerdict: Decodable {
        var canParkNow: Bool
        var level: String       // "green" | "yellow" | "red" | "unknown"
        var summary: String     // one-sentence plain-English verdict
        var restrictions: [String]
        var confidence: String  // "high" | "medium" | "low"

        var statusLevel: StatusLevel { StatusLevel(rawValue: level) ?? .unknown }
    }

    var baseURL: URL = Config.supabaseURL
    var anonKey: String = Config.supabaseAnonKey

    func interpret(_ image: UIImage) async throws -> SignVerdict {
        // Downscale before upload: sign text survives 1568px fine, and it
        // keeps upload time and vision token cost down.
        guard let jpeg = image.resized(maxDimension: 1568).jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotCreateFile)
        }

        var request = URLRequest(url: baseURL.appending(path: "/functions/v1/interpret-sign"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "image_base64": jpeg.base64EncodedString(),
            "media_type": "image/jpeg",
            "local_time": ISO8601DateFormatter().string(from: Date()),
            "timezone": "America/Halifax",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SignVerdict.self, from: data)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
