import SwiftUI

struct RootView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(DeviceCapabilities.self) private var caps
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var path: [Route] = []

    private let client = APIClientFactory.make()

    var body: some View {
        Group {
            if hasSeenOnboarding {
                NavigationStack(path: $path) {
                    TripPickerView(path: $path)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .tripPicker:
                                TripPickerView(path: $path)
                            case .bagSetup:
                                BagSetupView(path: $path)
                            case .itemList:
                                ItemListView(path: $path)
                            case .scan:
                                ScanView(client: client)
                            case .planViewer:
                                PlanViewerView()
                            case .rules:
                                RulesView()
                            case .inventoryScan:
                                InventoryScanView(path: $path, client: client)
                            case .arOverlay, .guidedScan:
                                GuidedScanView(path: $path, client: client)
                            case .suggestions:
                                SuggestionsView(path: $path)
                            case .beforeYouGo:
                                BeforeYouGoView()
                            }
                        }
                }
            } else {
                OnboardingView(hasSeen: $hasSeenOnboarding)
            }
        }
        .task { openPreviewPlanIfAsked() }
    }

    /// Debug builds launched with `-previewPlan` skip to the 3D plan with the fixture items in
    /// the checked bag, for checking the viewer without a trip or a scan.
    private func openPreviewPlanIfAsked() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-previewPlan"),
              let trip = AppFixtures.trips().first else { return }
        hasSeenOnboarding = true
        tripStore.trip = trip
        tripStore.bag = trip.checked
        itemsStore.items = AppFixtures.items()
        path = [.itemList, .planViewer]
        #endif
    }
}
