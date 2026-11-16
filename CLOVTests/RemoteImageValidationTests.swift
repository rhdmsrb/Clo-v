import Testing
@testable import CLOV

struct RemoteImageValidationTests {
    private func validate(
        status: Int = 200, final: String? = "a.supabase.co", requested: String? = "a.supabase.co",
        type: String? = "image/jpeg", length: Int64? = 1_000
    ) throws {
        try RemoteImageValidation.validate(
            statusCode: status, finalHost: final, requestedHost: requested, contentType: type, contentLength: length)
    }

    @Test("Accepts a same-host image under the cap")
    func accepts() throws { try validate() }

    @Test("Accepts a response with no Content-Length")
    func acceptsMissingLength() throws { try validate(length: nil) }

    @Test("Rejects non-2xx, redirected-host, non-image and oversized responses")
    func rejects() {
        #expect(throws: APIError.self) { try validate(status: 404) }
        #expect(throws: APIError.self) { try validate(final: "evil.example") }
        #expect(throws: APIError.self) { try validate(final: nil) }
        #expect(throws: APIError.self) { try validate(type: "text/html") }
        #expect(throws: APIError.self) { try validate(type: nil) }
        #expect(throws: APIError.self) { try validate(length: Int64(RemoteImageValidation.maxBytes) + 1) }
    }

    @Test("Host comparison ignores case")
    func hostCase() throws { try validate(final: "A.Supabase.co") }
}
