import SwiftUI

@main
struct PackFitApp: App {
    @State private var tripStore = TripStore()
    @State private var itemsStore = ItemsStore()
    @State private var planStore = PlanStore()
    @State private var rulesStore = RulesStore()
    @State private var capabilities = DeviceCapabilities()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tripStore)
                .environment(itemsStore)
                .environment(planStore)
                .environment(rulesStore)
                .environment(capabilities)
        }
    }
}
