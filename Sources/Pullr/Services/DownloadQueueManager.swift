import Foundation

final class DownloadQueueManager {
    private var services: [UUID: YTDLPService] = [:]
    private let lock = NSLock()

    var isRunning: Bool {
        lock.withLock { services.values.contains { $0.isRunning } }
    }

    func startDownload(
        itemID: UUID,
        ytDLPPath: String,
        arguments: [String],
        eventHandler: @escaping (YTDLPEvent) -> Void,
        completion: @escaping (Result<YTDLPResult, Error>) -> Void
    ) {
        let service = YTDLPService()
        lock.withLock { services[itemID] = service }

        service.start(
            ytDLPPath: ytDLPPath,
            arguments: arguments,
            eventHandler: eventHandler,
            completion: { [weak self] result in
                self?.lock.withLock { self?.services[itemID] = nil }
                completion(result)
            }
        )
    }

    func cancelDownload(itemID: UUID) {
        let service = lock.withLock { services.removeValue(forKey: itemID) }
        service?.cancel()
    }

    @discardableResult
    func pauseDownload(itemID: UUID) -> Bool {
        lock.withLock { services[itemID] }?.pause() ?? false
    }

    @discardableResult
    func resumeDownload(itemID: UUID) -> Bool {
        lock.withLock { services[itemID] }?.resume() ?? false
    }

    func cancelAllDownloads() {
        let runningServices = lock.withLock {
            let runningServices = Array(services.values)
            services.removeAll()
            return runningServices
        }
        for service in runningServices {
            service.cancel()
        }
    }

    func activeItemIDs() -> Set<UUID> {
        lock.withLock { Set(services.keys) }
    }
}
