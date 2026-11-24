import Foundation

/// Parses the free-text price field on the wardrobe item form. Prices are US
/// dollars, stored as `numeric(10, 2)`.
enum PriceInput {
    static let maximum: Decimal = 99_999_999.99
    static let currencyCode = "USD"

    enum ParseError: Error, Equatable {
        case notANumber, negative, tooLarge
    }

    /// Blank means "no price". Accepts "$1,299.5" style input and rounds to cents.
    static func parse(_ text: String) -> Result<Decimal?, ParseError> {
        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .success(nil) }
        let posix = Locale(identifier: "en_US_POSIX")
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }),
              let value = Decimal(string: cleaned, locale: posix) else { return .failure(.notANumber) }
        guard value >= 0 else { return .failure(.negative) }
        guard value <= maximum else { return .failure(.tooLarge) }
        return .success(rounded(value))
    }

    /// Plain text for pre-filling the field, e.g. "45" or "12.5".
    static func text(for price: Decimal?) -> String {
        guard let price else { return "" }
        return NSDecimalNumber(decimal: price).stringValue
    }

    static func formatted(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode).locale(Locale(identifier: "en_US")))
    }

    static func message(for error: ParseError) -> String {
        switch error {
        case .notANumber: "Enter the price as a number, like 49.99."
        case .negative: "The price can't be negative."
        case .tooLarge: "That price is too large."
        }
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }
}
