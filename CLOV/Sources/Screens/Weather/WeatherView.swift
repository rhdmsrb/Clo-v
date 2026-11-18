import SwiftUI

/// Pure dressing advice for a set of conditions, unit tested.
enum WeatherAdvice {
    private static let coldBelowC = 8.0
    private static let coolBelowC = 16.0
    private static let warmFromC = 26.0
    private static let windyFromKPH = 30.0

    /// One or two short lines, most important first.
    static func tips(for weather: LocalWeatherConditions) -> [String] {
        var tips: [String] = []
        let feels = weather.feelsLikeTemperatureC
        if weather.isSnowy {
            tips.append("Snow day: boots with grip and a warm outer layer.")
        } else if weather.isWet {
            tips.append("Rain likely: a water-resistant layer, and skip suede.")
        }
        if feels < coldBelowC {
            tips.append("Cold out. Layer up: knit, coat, and a scarf.")
        } else if feels < coolBelowC {
            tips.append("Cool. A light jacket or overshirt over your fit.")
        } else if feels >= warmFromC {
            tips.append("Warm. Breathable fabrics and lighter colors.")
        } else {
            tips.append("Mild. Almost anything works, so have fun with it.")
        }
        if weather.todayMaxWindKPH >= windyFromKPH {
            tips.append("Windy later: skip anything that flies away.")
        }
        return Array(tips.prefix(2))
    }
}

/// The Weather tab: today's conditions and what to wear, with a way into the
/// wardrobe-based outfit planner. Location is only requested when the user taps.
struct WeatherView: View {
    @StateObject private var weather = LocalWeatherPromptModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                conditionsCard
                NavigationLink {
                    WardrobeView()
                } label: {
                    Label("Plan an outfit from your wardrobe", systemImage: "hanger")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("weather.planOutfit")
            }
            .padding(.horizontal, Spacing.pageGutter)
            .padding(.top, Spacing.m)
        }
        .clearsTabBar()
        .background(Theme.background)
        .navigationBarHidden(true)
        .accessibilityIdentifier("weather.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Today")
                .font(Theme.serifGreeting)
                .foregroundStyle(Theme.mutedForeground)
            EditorialTitle("Dress for the", emphasis: "weather")
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    @ViewBuilder
    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let conditions = weather.conditions {
                conditionsSummary(conditions)
                ForEach(WeatherAdvice.tips(for: conditions), id: \.self) { tip in
                    Label(tip, systemImage: "sparkles")
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                }
            } else {
                Text("See today’s weather and what to wear for it.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                if let problem {
                    Text(problem)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                }
                Button {
                    weather.requestWeather()
                } label: {
                    Label(weather.isLoading ? "Checking the weather…" : "Check today’s weather",
                          systemImage: "location")
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(weather.isLoading)
                .accessibilityIdentifier("weather.check")
            }
        }
        .softCard(padding: Spacing.l)
    }

    private func conditionsSummary(_ conditions: LocalWeatherConditions) -> some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: conditions.icon)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(conditions.temperatureText)
                    .font(Theme.editorialFont(size: 34, weight: .regular))
                    .foregroundStyle(Theme.ink)
                Text("\(conditions.condition) · \(conditions.todayHighText) · \(conditions.rainChancePercent)% rain")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var problem: String? {
        if weather.locationDenied { return "Allow location access in Settings to see your local weather." }
        return weather.errorMessage
    }
}

#Preview("Weather") {
    NavigationStack { WeatherView() }
}
