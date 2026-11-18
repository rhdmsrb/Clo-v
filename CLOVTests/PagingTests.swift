import XCTest
@testable import CLOV

final class PagingTests: XCTestCase {
    private final class RequestLog {
        var ranges: [ClosedRange<Int>] = []
    }

    private func collect(total: Int, pageSize: Int) async throws -> (rows: [Int], requests: [ClosedRange<Int>]) {
        let log = RequestLog()
        let rows: [Int] = try await Paging.collectAll(pageSize: pageSize) { (range: ClosedRange<Int>) async throws -> [Int] in
            log.ranges.append(range)
            if range.lowerBound >= total { return [] }
            let last = min(range.upperBound, total - 1)
            return Array(range.lowerBound...last)
        }
        return (rows, log.ranges)
    }

    func testEmptyTableMakesOneRequest() async throws {
        let result = try await collect(total: 0, pageSize: 3)
        XCTAssertEqual(result.rows, [])
        XCTAssertEqual(result.requests, [0...2])
    }

    func testPartialPageStopsWithoutExtraRequest() async throws {
        let result = try await collect(total: 2, pageSize: 3)
        XCTAssertEqual(result.rows, [0, 1])
        XCTAssertEqual(result.requests.count, 1)
    }

    func testReadsEveryRowAcrossPages() async throws {
        let result = try await collect(total: 7, pageSize: 3)
        XCTAssertEqual(result.rows, Array(0..<7))
        XCTAssertEqual(result.requests, [0...2, 3...5, 6...8])
    }

    func testExactMultipleNeedsOneTrailingEmptyPage() async throws {
        let result = try await collect(total: 6, pageSize: 3)
        XCTAssertEqual(result.rows, Array(0..<6))
        XCTAssertEqual(result.requests, [0...2, 3...5, 6...8])
    }

    func testPropagatesErrorsInsteadOfReturningPartialResults() async {
        struct Boom: Error {}
        do {
            _ = try await Paging.collectAll(pageSize: 2) { range -> [Int] in
                if range.lowerBound > 0 { throw Boom() }
                return [0, 1]
            }
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}
