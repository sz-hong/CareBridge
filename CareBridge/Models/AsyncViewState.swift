import Foundation

struct AsyncViewState<Value> {
    private(set) var value: Value
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(value: Value) {
        self.value = value
    }

    mutating func beginLoading() {
        isLoading = true
        errorMessage = nil
    }

    mutating func finish(with newValue: Value) {
        value = newValue
        isLoading = false
        errorMessage = nil
    }

    mutating func fail(_ error: Error, fallbackMessage: String = "Request failed") {
        isLoading = false
        errorMessage = error.localizedDescription.isEmpty
            ? fallbackMessage
            : error.localizedDescription
    }

    mutating func updateValue(_ update: (inout Value) -> Void) {
        update(&value)
    }
}
