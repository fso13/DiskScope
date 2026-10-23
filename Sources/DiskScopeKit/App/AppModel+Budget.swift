import Foundation

extension AppModel {
    func notifyExceededBudgets(_ tree: ScanTree) {
        budget.notifyExceeded(tree: tree) { [weak self] status in
            self?.showToast(
                "Лимит превышен: \(URL(fileURLWithPath: status.budget.path).lastPathComponent) +"
                    + ByteFormat.string(status.overBy),
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }
}
