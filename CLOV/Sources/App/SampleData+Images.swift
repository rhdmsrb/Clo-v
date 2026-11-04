import UIKit

#if DEBUG
/// Answers `https://sample.clov.invalid/<kind>/<n>.jpg` requests with locally
/// rendered JPEGs, so sample photos load with no network. Registered on
/// `URLSession.shared` (AsyncImage) and added to `ImageCache`'s session.
final class SampleImageURLProtocol: URLProtocol {
    private static let canvas = CGSize(width: 600, height: 800)
    private static let jpegQuality: CGFloat = 0.8
    private static let hueStep = 0.137

    static func register() { URLProtocol.registerClass(SampleImageURLProtocol.self) }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SampleData.imageHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let components = url.pathComponents.filter { $0 != "/" }
        let kind = components.first ?? "photo"
        let number = Int((components.last ?? "0").prefix { $0.isNumber }) ?? 0
        let data = Self.render(kind: kind, number: number).jpegData(compressionQuality: Self.jpegQuality) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/jpeg"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: - Rendering

    private static func render(kind: String, number: Int) -> UIImage {
        let hue = (Double(number) * hueStep).truncatingRemainder(dividingBy: 1)
        let base = UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1)
        let accent = UIColor(hue: hue, saturation: 0.55, brightness: 0.45, alpha: 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let rect = CGRect(origin: .zero, size: canvas)
            let colors = [base.cgColor, accent.withAlphaComponent(0.7).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                     end: CGPoint(x: 0, y: canvas.height), options: [])
            }
            drawFigure(kind: kind, in: rect, color: accent.withAlphaComponent(0.85))
            drawLabel("\(kind) \(number)", in: rect)
        }
    }

    private static func drawFigure(kind: String, in rect: CGRect, color: UIColor) {
        color.setFill()
        if kind == "item" {
            UIBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.22), cornerRadius: 60).fill()
            return
        }
        let head = CGRect(x: rect.midX - 70, y: rect.height * 0.16, width: 140, height: 140)
        UIBezierPath(ovalIn: head).fill()
        let body = CGRect(x: rect.midX - 120, y: head.maxY + 16, width: 240, height: rect.height * 0.5)
        UIBezierPath(roundedRect: body, cornerRadius: 80).fill()
    }

    private static func drawLabel(_ text: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 34), .foregroundColor: UIColor.white
        ]
        (text as NSString).draw(at: CGPoint(x: 28, y: rect.height - 70), withAttributes: attributes)
    }
}
#endif
