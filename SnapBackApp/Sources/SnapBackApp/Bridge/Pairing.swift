import Foundation
import CoreImage

public enum Pairing {
    /// Build the pairing URL scanned by SnapBack Mobile. Shape:
    ///   snapback-pair://v1?token=<64-hex>&desk=<URL-encoded name>&v=1
    public static func pairingURL(token: Data, deskName: String) -> String {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        // URLComponents encodes the query safely (spaces → %20, ' → %27, etc.).
        var comps = URLComponents()
        comps.scheme = "snapback-pair"
        comps.host = "v1"
        comps.queryItems = [
            URLQueryItem(name: "token", value: hex),
            URLQueryItem(name: "desk", value: deskName),
            URLQueryItem(name: "v", value: "1")
        ]
        var query = comps.percentEncodedQuery ?? ""
        // Some SDK versions don't percent-encode apostrophes; ensure %27 for URL safety.
        query = query.replacingOccurrences(of: "'", with: "%27")
        return "snapback-pair://v1?" + query
    }

    /// Generate a QR image for `url`. Nil on unexpected CoreImage failure.
    public static func qrImage(for url: String, scale: CGFloat = 8.0) -> CGImage? {
        guard let data = url.data(using: .utf8) else { return nil }
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(transformed, from: transformed.extent)
    }
}
