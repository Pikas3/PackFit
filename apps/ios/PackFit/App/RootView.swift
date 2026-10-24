import SwiftUI

struct RootView: View {
    @Environment(TripStore.self) private var tripStore
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
                                ScanView(client: client, hasLidar: caps.hasLidar)
                            case .planViewer:
                                PlanViewerView()
                            case .rules:
                                RulesView()
                            case .arOverlay:
                                Text("AR overlay is a stretch goal — not enabled yet.")
                                    .packFitScreenPadding()
                            }
                        }
                }
            } else {
                OnboardingView(hasSeen: $hasSeenOnboarding)
            }
        }
    }
}
