import Foundation
import Testing
@testable import CareBridge

private struct SampleError: LocalizedError {
    var errorDescription: String? { "Network unavailable" }
}

struct AsyncViewStateTests {
    @Test func tracksLoadingAndLoadedState() {
        var state = AsyncViewState<[String]>(value: [])

        state.beginLoading()
        #expect(state.isLoading)
        #expect(state.errorMessage == nil)

        state.finish(with: ["care-log"])
        #expect(!state.isLoading)
        #expect(state.value == ["care-log"])
        #expect(state.errorMessage == nil)
    }

    @Test func keepsExistingValueWhenLoadFails() {
        var state = AsyncViewState(value: ["cached"])

        state.beginLoading()
        state.fail(SampleError())

        #expect(!state.isLoading)
        #expect(state.value == ["cached"])
        #expect(state.errorMessage == "Network unavailable")
    }

    @Test func updatesValueWithoutChangingLoadedState() {
        var state = AsyncViewState(value: [1, 2])
        state.finish(with: [1, 2])

        state.updateValue { items in
            items.insert(0, at: 0)
        }

        #expect(state.value == [0, 1, 2])
        #expect(!state.isLoading)
    }
}
