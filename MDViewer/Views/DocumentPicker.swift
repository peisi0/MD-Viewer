import UIKit
import UniformTypeIdentifiers

/// Presents the Files document browser and imports the user's selection.
///
/// Two deliberate choices make this work under sideload hosts (LiveContainer /
/// SideStore), where SwiftUI's `.fileImporter` often returns a URL the guest
/// app cannot read:
///  1. `asCopy: true` — the system copies each picked file into this app's
///     temp directory first, so the delegate gets a plain local URL with no
///     security scope to negotiate.
///  2. Direct UIKit `present(_:)` — the picker is a remote view service and
///     must be presented modally; embedding it in a SwiftUI sheet/cover can
///     render an empty white screen.
@MainActor
final class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    var onPick: (([URL]) -> Void)?
    var onCancel: (() -> Void)?

    /// Delegate callbacks arrive later, so keep the presenter alive until one
    /// of them fires. The cycle is broken in both callbacks.
    private var retained: DocumentPickerPresenter?

    func present() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: UTType.importableTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = self

        guard let host = Self.topPresentedController() else {
            onCancel?()
            return
        }
        retained = self
        host.present(picker, animated: true)
    }

    private static func topPresentedController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        retained = nil
        onPick?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        retained = nil
        onCancel?()
    }
}
