import Foundation
import Supabase

enum AppConfig {
    // Same Supabase project the Next.js web prototype uses
    // (../prototype/.env.local) — one backend, two clients.
    static let supabaseURL = URL(string: "https://exbozksjwpyvstqhcyqy.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_wlceXdLHdxHp5brmwrg12Q_glPGikbe"
}

enum SupabaseManager {
    static let client: SupabaseClient = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = PostgresDateFormatters.withFractional.date(from: string) {
                return date
            }
            if let date = PostgresDateFormatters.plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(string)"
            )
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        return SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                db: SupabaseClientOptions.DatabaseOptions(
                    encoder: encoder,
                    decoder: decoder
                )
            )
        )
    }()
}

private enum PostgresDateFormatters {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
