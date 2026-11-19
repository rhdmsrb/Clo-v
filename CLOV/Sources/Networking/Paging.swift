import Foundation

/// Reads a whole table slice in fixed-size pages. PostgREST silently truncates
/// a single response at the project's max-rows setting (default 1000), so a
/// plain `.select()` on a growing list returns a short, wrong result.
///
/// `pageSize` must not exceed the project's `max_rows`; a page shorter than
/// `pageSize` is treated as the last one.
enum Paging {
    static let pageSize = 1000

    static func collectAll<Row>(
        pageSize: Int = Paging.pageSize,
        fetchPage: (_ rows: ClosedRange<Int>) async throws -> [Row]
    ) async throws -> [Row] {
        precondition(pageSize > 0, "pageSize must be positive")
        var collected: [Row] = []
        var start = 0
        while true {
            let page = try await fetchPage(start...(start + pageSize - 1))
            collected.append(contentsOf: page)
            if page.count < pageSize { return collected }
            start += pageSize
        }
    }
}
