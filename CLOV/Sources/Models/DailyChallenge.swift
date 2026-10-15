import Foundation

struct DailyChallenge: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let occasion: String
    let accent: String

    static var today: DailyChallenge {
        let challenges = [
            DailyChallenge(id: "lecture", title: "LECTURE FIT", prompt: "What would you wear to class today?", occasion: "Everyday", accent: "🎓"),
            DailyChallenge(id: "rain", title: "RAINY DAY", prompt: "Build a look that survives the walk across campus.", occasion: "Everyday", accent: "☔️"),
            DailyChallenge(id: "date", title: "DATE NIGHT", prompt: "Pick the look that makes the best first impression.", occasion: "Date", accent: "✨"),
            DailyChallenge(id: "interview", title: "INTERVIEW MODE", prompt: "Which fit says confident and prepared?", occasion: "Interview", accent: "📓"),
            DailyChallenge(id: "weekend", title: "WEEKEND PLANS", prompt: "Choose the outfit for your next spontaneous plan.", occasion: "Travel", accent: "🧢")
        ]
        let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: Date()) ?? 0
        return challenges[day % challenges.count]
    }

    static func forWeather(_ weather: LocalWeatherConditions) -> DailyChallenge {
        if weather.isSnowy || weather.todayLowC <= 4 || weather.feelsLikeTemperatureC <= 4 {
            return DailyChallenge(id: "weather-cold", title: "COLD-WEATHER LAYERS",
                                  prompt: "Style a warm coat, a soft layer, and shoes made for chilly days.",
                                  occasion: "Everyday", accent: "❄️")
        }
        if weather.isWet {
            return DailyChallenge(id: "weather-rain", title: "RAIN-READY LOOK",
                                  prompt: "Build a look with a light waterproof layer and shoes for wet sidewalks.",
                                  occasion: "Everyday", accent: "☔️")
        }
        if weather.todayHighC >= 29 || weather.feelsLikeTemperatureC >= 29 {
            return DailyChallenge(id: "weather-hot", title: "HOT-DAY DRESSING",
                                  prompt: "Choose breathable fabrics and an easy layer for the heat.",
                                  occasion: "Everyday", accent: "☀️")
        }
        if weather.todayMaxWindKPH >= 28 || weather.windKPH >= 28 || weather.todayLowC <= 15 || weather.feelsLikeTemperatureC <= 15 {
            return DailyChallenge(id: "weather-wind", title: "LIGHT LAYER WEATHER",
                                  prompt: "Put together a look with a jacket or overshirt for the breeze.",
                                  occasion: "Everyday", accent: "🧥")
        }
        if weather.todayWeatherCode == 0 || weather.weatherCode == 0 || weather.todayHighC >= 22 || weather.feelsLikeTemperatureC >= 22 {
            return DailyChallenge(id: "weather-sunny", title: "SUNNY-DAY STYLE",
                                  prompt: "Pick an airy look and an extra layer for later in the day.",
                                  occasion: "Everyday", accent: "☀️")
        }
        return DailyChallenge(id: "weather-mild", title: "MILD-DAY LOOK",
                              prompt: "Style an easy outfit with a layer you can take off as the day warms up.",
                              occasion: "Everyday", accent: "🌤️")
    }
}
