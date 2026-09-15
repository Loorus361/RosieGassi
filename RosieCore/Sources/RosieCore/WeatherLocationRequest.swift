import Foundation

/// Request-scoped continuation + deadline shared by real and injected location providers.
@MainActor
public final class WeatherLocationRequest {
    public private(set) var currentID: UUID?
    public private(set) var requestedAt = Date()
    private let timeout: Duration
    private var continuation: CheckedContinuation<WeatherCoordinate?, Never>?
    private var deadline: Task<Void, Never>?
    private var stop: (() -> Void)?

    public init(timeout: Duration = .seconds(8)) { self.timeout = timeout }

    public func coordinate(start: (UUID) -> Void, stop: @escaping () -> Void) async -> WeatherCoordinate? {
        cancel()
        let id = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.stop = stop
                currentID = id
                requestedAt = Date()
                deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.complete(nil, id: id)
                }
                start(id)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(nil, id: id) }
        }
    }

    public func cancel() { if let currentID { complete(nil, id: currentID) } }

    public func complete(_ coordinate: WeatherCoordinate?, id: UUID) {
        guard currentID == id else { return }
        currentID = nil
        deadline?.cancel(); deadline = nil
        let pending = continuation; continuation = nil
        let stopProvider = stop; stop = nil
        stopProvider?()
        pending?.resume(returning: coordinate)
    }
}
