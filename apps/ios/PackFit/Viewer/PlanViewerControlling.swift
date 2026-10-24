import Foundation

@MainActor
protocol PlanViewerControlling: AnyObject {
    func goToStep(_ n: Int, animated: Bool)
    var currentStep: Int { get }
    var onStepChange: ((Int) -> Void)? { get set }
}
