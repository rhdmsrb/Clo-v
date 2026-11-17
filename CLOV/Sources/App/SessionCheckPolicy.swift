import Auth
import Foundation

/// Decides what a failed foreground session check means. Only a definitive
/// "this session is no longer valid" answer from the auth service should log
/// the user out; outages, rate limits and unknown failures must keep the
/// stored session so the next check can retry.
enum SessionCheckPolicy {
    private static let invalidSessionCodes: Set<ErrorCode> = [
        .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed,
        .userNotFound, .userBanned, .badJWT, .invalidJWT,
    ]
    private static let unauthorizedStatus = 401

    static func shouldSignOut(after error: Error) -> Bool {
        if error is URLError || error is CancellationError { return false }
        guard let authError = error as? AuthError else { return false }
        switch authError {
        case .sessionMissing:
            return true
        case let .api(_, errorCode, _, response):
            return invalidSessionCodes.contains(errorCode) || response.statusCode == unauthorizedStatus
        default:
            return false
        }
    }
}
