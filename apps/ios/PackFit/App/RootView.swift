import SwiftUI

struct RootView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(PlanStore.self) private var planStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var navigator = AppNavigator()
    @State private var homePath: [Route] = []
    @State private var resultsPath: [Route] = []
    @State private var planPath: [Route] = []

    private let client = APIClientFactory.make()

    var body: some View {
        Group {
            if hasSeenOnboarding {
                TabView(selection: $navigator.tab) {
                    Tab(Copy.Tabs.home, systemImage: "house", value: AppTab.home) {
                        stack(path: $homePath) { DashboardView(path: $homePath) }
                    }
                    Tab(Copy.Tabs.results, systemImage: "shippingbox", value: AppTab.results) {
                        stack(path: $resultsPath) { PlanViewerView(path: $resultsPath) }
                    }
                    Tab(Copy.Tabs.plan, systemImage: "checklist", value: AppTab.plan) {
                        stack(path: $planPath) { PackingPlanView(path: $planPath) }
                    }
                }
                .environment(navigator)
                .loadingModal(
                    isPresented: planStore.isPacking,
                    title: Copy.Loading.packingTitle,
                    message: Copy.Loading.packingWait
                )
            } else {
                OnboardingView(hasSeen: $hasSeenOnboarding)
            }
        }
        .tint(Tokens.Palette.pink700)
        .font(Tokens.TypeScale.base)
        .task { openPreviewPlanIfAsked() }
    }

    private func stack<Content: View>(path: Binding<[Route]>, @ViewBuilder root: () -> Content) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route, path: path)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route, path: Binding<[Route]>) -> some View {
        switch route {
        case .tripPicker:
            DashboardView(path: path)
        case .bagSetup:
            BagSetupView(path: path)
        case .itemList:
            ItemListView(path: path)
        case .planViewer:
            PlanViewerView(path: path)
        case .rules:
            RulesView()
        case .inventoryScan:
            InventoryScanView(path: path, client: client)
        case .suggestions:
            SuggestionsView(path: path)
        case .beforeYouGo:
            BeforeYouGoView()
        }
    }

    /// Debug builds launched with `-previewPlan` skip to the results with the fixture items in
    /// the checked bag, for checking the viewer without a trip or a scan. `-previewTab plan`,
    /// `home`, `suggestions` or `items` opens another screen instead.
    private func openPreviewPlanIfAsked() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-previewPlan"), var trip = AppFixtures.trips().first else { return }
        // `-previewDepart yyyy-MM-dd` moves the trip, e.g. into the 16-day forecast range.
        if let depart = UserDefaults.standard.string(forKey: "previewDepart") { trip.departDate = depart }
        hasSeenOnboarding = true
        tripStore.trip = trip
        // `-previewNoBag` leaves the bag unset, to check the screens that ask for one.
        tripStore.bag = args.contains("-previewNoBag") ? nil : trip.checked
        // `-previewNoItems` starts with an empty list, e.g. to see every packing idea on Home.
        itemsStore.items = args.contains("-previewNoItems") ? [] : AppFixtures.items()
        tripStore.suggestions = AppFixtures.tripSuggestFallback(for: trip).suggestions
        switch UserDefaults.standard.string(forKey: "previewTab") {
        case "suggestions":
            navigator.tab = .home
            homePath = [.suggestions]
        case "items":
            navigator.tab = .home
            homePath = [.itemList]
        case "plan": navigator.tab = .plan
        case "home": navigator.tab = .home
        default: navigator.tab = .results
        }
        #endif
    }
}
