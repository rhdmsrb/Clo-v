import SwiftUI

/// Feed hero: today's prompt on the brand gradient with one CTA.
struct DailyChallengeCard: View {
    @Environment(\.openURL) private var openURL
    let challenge: DailyChallenge
    let weather: LocalWeatherConditions?
    let isWeatherLoading: Bool
    let locationDenied: Bool
    let errorMessage: String?
    let onUseWeather: () -> Void
    let onJoin: () -> Void

    @State private var showInfo = false
    @ScaledMetric(relativeTo: .largeTitle) private var decorationSize: CGFloat = 120

    private static let weatherCreditURL = URL(string: "https://open-meteo.com/")
    private static let decorationOpacity = 0.14
    private static let pillFill = Color.white.opacity(0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            title
            Text(challenge.prompt)
                .font(Theme.body)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            if weather == nil, let errorMessage {
                Text(errorMessage).font(Theme.caption).foregroundStyle(Color.white)
            }
            joinButton.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(alignment: .topTrailing) { decoration }
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .elevatedShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyChallengeCard")
    }

    /// One row when it fits; at large text sizes the label and the
    /// weather/info controls stack instead of truncating.
    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                promptLabel.lineLimit(1)
                Spacer(minLength: 0)
                weatherPill
                infoButton
            }
            VStack(alignment: .leading, spacing: 8) {
                promptLabel
                HStack(spacing: 8) {
                    weatherPill
                    Spacer(minLength: 0)
                    infoButton
                }
            }
        }
    }

    private var promptLabel: some View {
        Text("Today's prompt")
            .font(Theme.caption)
            .foregroundStyle(Color.white)
            .textCase(.uppercase)
    }

    private var title: some View {
        Text(challenge.title.capitalized)
            .font(Theme.displayFont)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityAddTraits(.isHeader)
    }

    private var joinButton: some View {
        Button(action: onJoin) {
            HStack(spacing: 8) {
                Text("Join today's challenge")
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }
            .font(Theme.headline)
            .foregroundStyle(Theme.accentForeground)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.accent, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var decoration: some View {
        Image(systemName: challengeSymbol)
            .font(.system(size: decorationSize))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.white.opacity(Self.decorationOpacity))
            .offset(x: 28, y: -18)
            .accessibilityHidden(true)
    }

    // MARK: Weather

    /// One compact pill: current conditions, or the action to fetch them.
    @ViewBuilder
    private var weatherPill: some View {
        if let weather {
            Label(weather.summary, systemImage: weather.icon)
                .font(Theme.caption)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(Self.pillFill, in: Capsule(style: .continuous))
        } else {
            Button {
                if locationDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settings)
                } else {
                    onUseWeather()
                }
            } label: {
                weatherPillLabel
            }
            .buttonStyle(.plain)
            .disabled(isWeatherLoading)
        }
    }

    private var weatherPillLabel: some View {
        HStack(spacing: 6) {
            if isWeatherLoading {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "location.fill").accessibilityHidden(true)
                Text(locationDenied ? "Open Settings" : "Use weather")
            }
        }
        .font(Theme.caption)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTapSize)
        .background(Self.pillFill, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }

    private var infoButton: some View {
        Button { showInfo = true } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About weather and privacy")
        .popover(isPresented: $showInfo) { infoPopover }
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Privacy disclosure: shown only before weather is used.
            if weather == nil {
                Text("Your location is sent to Open-Meteo to get current weather; CLO-V doesn't save it.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
            }
            if let creditURL = Self.weatherCreditURL {
                Link("Weather data by Open-Meteo", destination: creditURL)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(minHeight: Theme.minTapSize, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.cardElevated)
        .presentationCompactAdaptation(.popover)
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
