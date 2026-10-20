import XCTest
@testable import CLOV

final class ImageCacheKeyTests: XCTestCase {
    func testSignedURLsForSameObjectShareAKey() throws {
        let a = try XCTUnwrap(URL(string: "https://x.supabase.co/storage/v1/object/sign/fit/a.jpg?token=one"))
        let b = try XCTUnwrap(URL(string: "https://x.supabase.co/storage/v1/object/sign/fit/a.jpg?token=two"))
        XCTAssertEqual(ImageCache.key(for: a), ImageCache.key(for: b))
    }

    func testDifferentObjectsGetDifferentKeys() throws {
        let a = try XCTUnwrap(URL(string: "https://x.supabase.co/storage/v1/object/sign/fit/a.jpg?token=one"))
        let b = try XCTUnwrap(URL(string: "https://x.supabase.co/storage/v1/object/sign/fit/b.jpg?token=one"))
        XCTAssertNotEqual(ImageCache.key(for: a), ImageCache.key(for: b))
    }

    func testDifferentHostsGetDifferentKeys() throws {
        let a = try XCTUnwrap(URL(string: "https://a.example.com/p.jpg"))
        let b = try XCTUnwrap(URL(string: "https://b.example.com/p.jpg"))
        XCTAssertNotEqual(ImageCache.key(for: a), ImageCache.key(for: b))
    }
}
