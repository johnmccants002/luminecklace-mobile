import Combine
import Foundation

@MainActor
final class ShareLumiViewModel: ObservableObject {
    static let defaultMessage = "This made me think of you."

    @Published private(set) var state: ShareLumiState = .extracting
    @Published private(set) var extractedLink: ExtractedShareLink?
    @Published private(set) var necklaces: [ShareNecklace] = []
    @Published var selectedNecklaceID: String?
    @Published var message = ShareLumiViewModel.defaultMessage {
        didSet {
            if message.count > 500 {
                message = String(message.prefix(500))
            }
        }
    }
    @Published var destination: ShareQueueDestination = .upNext

    let clientRequestId: UUID

    private let extractor: any ShareItemExtracting
    private let service: any ShareLumiServicing
    private let onComplete: () -> Void
    private let onCancel: () -> Void
    private var activeTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var inputItems: [NSExtensionItem] = []
    private var hasStarted = false
    private var hasCompleted = false

    init(
        extractor: any ShareItemExtracting = ShareItemExtractor(),
        service: any ShareLumiServicing = ShareLumiService(),
        clientRequestId: UUID = UUID(),
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.extractor = extractor
        self.service = service
        self.clientRequestId = clientRequestId
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var selectedNecklace: ShareNecklace? {
        necklaces.first { $0.id == selectedNecklaceID }
    }

    var canSubmit: Bool {
        state == .ready && selectedNecklace != nil && extractedLink != nil
    }

    func start(items: [NSExtensionItem]) {
        guard !hasStarted else { return }
        hasStarted = true
        inputItems = items
        extractAndLoad()
    }

    func tryAgain() {
        guard state != .submitting else { return }
        if extractedLink != nil, selectedNecklace != nil, !necklaces.isEmpty {
            state = .ready
            submit()
            return
        }
        extractAndLoad()
    }

    func submit() {
        guard canSubmit,
              activeTask == nil,
              let necklace = selectedNecklace,
              let link = extractedLink else {
            return
        }

        state = .submitting
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CreateSharedLumiRequest(
            clientRequestId: clientRequestId,
            url: link.url.absoluteString,
            text: trimmed.isEmpty ? nil : trimmed,
            destination: destination
        )
        activeTask = Task { [weak self, service] in
            do {
                _ = try await service.createSharedLumi(necklaceId: necklace.id, request: request)
                guard let self, !Task.isCancelled else { return }
                self.activeTask = nil
                self.state = .success
                self.scheduleCompletion()
            } catch is CancellationError {
                self?.activeTask = nil
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.activeTask = nil
                self.handle(error)
            }
        }
    }

    func cancel() {
        cancelTasks()
        guard !hasCompleted else { return }
        hasCompleted = true
        onCancel()
    }

    func cancelTasks() {
        activeTask?.cancel()
        completionTask?.cancel()
        activeTask = nil
        completionTask = nil
    }

    private func extractAndLoad() {
        activeTask?.cancel()
        state = .extracting
        activeTask = Task { [weak self, extractor, service] in
            guard let self else { return }
            do {
                guard let link = try await extractor.extract(from: self.inputItems) else {
                    guard !Task.isCancelled else { return }
                    self.activeTask = nil
                    self.state = .unsupportedShare
                    return
                }
                guard !Task.isCancelled else { return }
                self.extractedLink = link
                self.state = .loadingNecklaces

                let eligible = try await service.fetchEligibleNecklaces()
                guard !Task.isCancelled else { return }
                self.activeTask = nil
                self.necklaces = eligible
                guard !eligible.isEmpty else {
                    self.state = .noEligibleNecklaces
                    return
                }

                if let primary = eligible.first(where: \.isPrimary) {
                    self.selectedNecklaceID = primary.id
                } else if self.selectedNecklaceID.flatMap({ selected in
                    eligible.first(where: { $0.id == selected })
                }) == nil {
                    self.selectedNecklaceID = eligible.first?.id
                }
                self.state = .ready
            } catch is CancellationError {
                self.activeTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.activeTask = nil
                self.handle(error)
            }
        }
    }

    private func handle(_ error: Error) {
        if let serviceError = error as? ShareLumiServiceError,
           serviceError == .authenticationRequired {
            state = .authenticationRequired
            return
        }
        if let serviceError = error as? ShareLumiServiceError,
           serviceError == .conflict {
            state = .failure(message: serviceError.errorDescription ?? "This Lumi couldn’t be added safely.")
            return
        }
        state = .failure(
            message: (error as? LocalizedError)?.errorDescription
                ?? "Lumi couldn’t connect. Check your connection and try again."
        )
    }

    private func scheduleCompletion() {
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, !Task.isCancelled, !self.hasCompleted else { return }
            self.hasCompleted = true
            self.onComplete()
        }
    }
}
