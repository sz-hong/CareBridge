import Foundation
import Testing
@testable import CareBridge

struct HealthThresholdSettingsTests {
    @Test func decodesDecimalThresholdReturnedAsString() throws {
        let json = Data("""
        {
          "heart_rate_high": 105,
          "heart_rate_low": 48,
          "blood_oxygen_low": "92.5"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let thresholds = try decoder.decode(HealthAlertThresholdSettings.self, from: json)

        #expect(thresholds.heartRateHigh == 105)
        #expect(thresholds.heartRateLow == 48)
        #expect(thresholds.bloodOxygenLow == 92.5)
    }
}
