import CloudKit
import SwiftUI
import UIKit

/// Apple's standard "invite people via Messages / Mail / link" sheet for a CKShare.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onChange: () -> Void

        init(onChange: @escaping () -> Void) { self.onChange = onChange }

        func itemTitle(for csc: UICloudSharingController) -> String? { "Sunday Dinners" }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onChange()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
    }
}
