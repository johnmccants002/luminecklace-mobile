import SwiftUI
import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareLumiRootView>?
    private var didFinishRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 620)

        let viewModel = ShareLumiViewModel(
            onComplete: { [weak self] in self?.completeRequest() },
            onCancel: { [weak self] in self?.cancelRequest() }
        )
        let hostingController = UIHostingController(
            rootView: ShareLumiRootView(viewModel: viewModel)
        )
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        viewModel.start(items: extensionContext?.inputItems as? [NSExtensionItem] ?? [])
    }

    private func completeRequest() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancelRequest() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: NSCocoaErrorDomain,
                code: NSUserCancelledError,
                userInfo: nil
            )
        )
    }
}
