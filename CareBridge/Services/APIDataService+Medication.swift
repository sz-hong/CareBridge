import Foundation

extension APIDataService {
    // MARK: - Medication
    func fetchMedications(elderId: String) async throws -> [Medication] { try await get(path: APIEndpoint.medications) }
    func createMedication(_ medication: Medication) async throws -> Medication { try await post(path: APIEndpoint.medications, body: medication) }
    func updateMedication(_ medication: Medication) async throws -> Medication { try await put(path: APIEndpoint.medication(id: medication.id), body: medication) }
    func deleteMedication(id: String) async throws { try await delete(path: APIEndpoint.medication(id: id)) }
    func fetchTodayConfirmations() async throws -> [MedicationConfirmation] { try await get(path: APIEndpoint.medicationTodayConfirmations) }
    func confirmMedication(id: String, request: ConfirmMedicationRequest) async throws -> MedicationConfirmation {
        try await post(path: APIEndpoint.medicationConfirm(id: id), body: request)
    }
}
