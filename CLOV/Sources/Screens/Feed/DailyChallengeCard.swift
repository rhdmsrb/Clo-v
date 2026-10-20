import SwiftUI

struct DailyChallengeCard: View {
    @Environment(\.openURL) private var openURL
    let challenge: DailyChallenge
    let weather: LocalWeatherConditions?
    let isWeatherLoading: Bool
    let locationDenied: Bool
    let errorMessage: String?
    let onUseWeather: () -> Void
    let onJoin: () -> Void

    private static let weatherCreditURL = URL(string: "https://open-meteo.com/")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            promptButton
            weatherRow
            if weather == nil, let errorMessage {
                Text(errorMessage)
                    .font(.caption2).foregroundStyle(Theme.mutedForeground)
            }
            Text("Your location is sent to Open-Meteo to get current weather; CLO-V doesn't save it.")
                .font(.caption2).foregroundStyle(Theme.mutedForeground.opacity(0.85))
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyChallengeCard")
    }

    private var promptButton: some View {
        Button(action: onJoin) {
            HStack(spacing: 12) {
                Image(systemName: challengeSymbol)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's prompt")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.mutedForeground)
                    Text(challenge.title)
                        .font(Theme.editorialFont(size: 23, relativeTo: .title3))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(challenge.prompt)
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var weatherRow: some View {
        HStack(spacing: 8) {
            if let weather {
                Label(weather.summary, systemImage: weather.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                if let creditURL = Self.weatherCreditURL {
                    Link(destination: creditURL) {
                        Text("Weather · Open-Meteo").font(.caption2.weight(.medium))
                    }
                }
            } else {
                Image(systemName: "location.circle")
                    .font(.caption).foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
                Text("Dress for your local weather")
                    .font(.caption2).foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: 2)
                weatherButton
            }
        }
    }

    private var weatherButton: some View {
        Button {
            if locationDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                openURL(settings)
            } else {
                onUseWeather()
            }
        } label: {
            if isWeatherLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(locationDenied ? "Open Settings" : "Use local weather")
                    .font(.caption2.weight(.semibold))
            }
        }
        .disabled(isWeatherLoading)
        .foregroundStyle(Theme.accent)
    }

    private var challengeSymbol: String {
        switch challenge.id {
        case "weather-rain", "rain": "cloud.rain"
        case "weather-cold", "weather-snow": "snowflake"
        case "weather-hot", "weather-sunny": "sun.max"
        case "weather-wind": "wind"
        case "lecture": "graduationcap"
        case "date": "sparkles"
        case "interview": "briefcase"
        default: "sun.max"
        }
    }
}
