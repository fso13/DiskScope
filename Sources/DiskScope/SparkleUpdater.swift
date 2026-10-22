import AppKit
import DiskScopeKit
import Sparkle

/// Thin wrapper so the app target is the only place that depends on Sparkle.
@MainActor
final class SparkleUpdater {
    private var controller: SPUStandardUpdaterController?

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty, key != "__SPARKLE_PUBLIC_KEY__" else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = L10n.t("Обновления не настроены в этой сборке")
            alert.informativeText = L10n.t("Задайте SUPublicEDKey и SUFeedURL при сборке релиза.")
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }
}
