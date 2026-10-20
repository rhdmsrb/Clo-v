import XCTest
@testable import CLOV

final class DailyChallengeTests: XCTestCase {
    private func weather(
        temp: Double = 18, feelsLike: Double = 18, precip: Double = 0, rain: Double = 0,
        showers: Double = 0, snow: Double = 0, code: Int = 3, wind: Double = 5,
        low: Double = 16, high: Double = 20, rainChance: Int = 0, maxWind: Double = 10,
        todayCode: Int = 3
    ) -> LocalWeatherConditions {
        LocalWeatherConditions(
            temperatureC: temp, feelsLikeC: feelsLike, precipitationMM: precip, rainMM: rain,
            showersMM: showers, snowfallCM: snow, weatherCode: code, windKPH: wind,
            todayLowC: low, todayHighC: high, rainChancePercent: rainChance,
            todayMaxWindKPH: maxWind, todayWeatherCode: todayCode
        )
    }

    func testTodayIsStableWithinADay() {
        XCTAssertEqual(DailyChallenge.today, DailyChallenge.today)
    }

    func testFreezingLowPicksColdLayers() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(low: 2)).id, "weather-cold")
    }

    func testSnowBeatsRain() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(snow: 1, rainChance: 80)).id, "weather-cold")
    }

    func testRainChanceAtFortyPercentPicksRain() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(rainChance: 40)).id, "weather-rain")
        XCTAssertNotEqual(DailyChallenge.forWeather(weather(rainChance: 39)).id, "weather-rain")
    }

    func testHeatPicksHotDay() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(high: 31)).id, "weather-hot")
    }

    func testStrongWindPicksLightLayer() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(maxWind: 30)).id, "weather-wind")
    }

    func testClearWarmDayPicksSunny() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(code: 0, low: 18, high: 24)).id, "weather-sunny")
    }

    func testMildDayIsFallback() {
        XCTAssertEqual(DailyChallenge.forWeather(weather(feelsLike: 20, low: 18, high: 20)).id, "weather-mild")
    }
}
