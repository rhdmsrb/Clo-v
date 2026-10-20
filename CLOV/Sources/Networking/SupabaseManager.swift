import Foundation
import Supabase

enum AppConfig {
    // Same Supabase project the Next.js web prototype uses
    // (../prototype/.env.local) — one backend, two clients.
    static let supabaseURL = URL(string: "https://exbozksjwpyvstqhcyqy.supabase.co")!
    /// Deep link the password-reset email returns to. Must also be listed under
    /// Authentication > URL Configuration > Redirect URLs in the Supabase dashboard.
    static let authCallbackURL = URL(string: "clov://auth-callback")!
    static let supabaseAnonKey = "sb_publishable_wlceXdLHdxHp5brmwrg12Q_glPGikbe"
}

enum SupabaseManager {
    #if DEBUG && targetEnvironment(simulator)
    // Simulator builds are often installed unsigned (CODE_SIGNING_ALLOWED=NO),
    // where Keychain writes can fail without the app's signing entitlements.
    // Keep test sessions in UserDefaults for Debug only; Release continues to
    // use Supabase's Keychain-backed default storage.
    private struct DebugAuthStorage: AuthLocalStorage {
        func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: key) }
        func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: key) }
        func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: key) }
    }
    #endif

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

        #if DEBUG && targetEnvironment(simulator)
        let authOptions = SupabaseClientOptions.AuthOptions(storage: DebugAuthStorage())
        #else
        let authOptions = SupabaseClientOptions.AuthOptions()
        #endif

        return SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                db: SupabaseClientOptions.DatabaseOptions(
                    encoder: encoder,
                    decoder: decoder
                ),
                auth: authOptions
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
