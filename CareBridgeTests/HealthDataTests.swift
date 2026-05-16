import Foundation
import Testing
@testable import CareBridge

struct HealthDataTests {
    @Test func dashboardDecodingIgnoresBloodPressureAndKeepsActiveEnergy() throws {
        let json = Data("""
        {
          "heart_rate": {
            "id": "hr",
            "value": 72,
            "recorded_at": "2026-05-16T00:00:00Z"
          },
          "active_energy": {
            "id": "energy",
            "value": 245.5,
            "recorded_at": "2026-05-16T00:05:00Z"
          },
          "blood_pressure_systolic": {
            "id": "bp",
            "value": 140,
            "recorded_at": "2026-05-16T00:10:00Z"
          }
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let dashboard = try decoder.decode(HealthData.self, from: json)

        #expect(dashboard.heartRate == 72)
        #expect(dashboard.activeEnergy == 245.5)
        #expect(dashboard.bloodPressureSystolic == 0)
        #expect(dashboard.bloodPressureDiastolic == 0)
    }
}
