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
        hevcFFmpegPath: String? = nil,
        eventHandler: @escaping (YTDLPEvent) -> Void,
        completion: @escaping (Result<YTDLPResult, Error>) -> Void
    ) {
        let service = YTDLPService()
        lock.withLock { services[itemID] = service }

        service.start(
            ytDLPPath: ytDLPPath,
            arguments: arguments,
            hevcFFmpegPath: hevcFFmpegPath,
            eventHandler: { [weak self] event in
                guard self?.lock.withLock({ self?.services[itemID] === service }) == true else { return }
                eventHandler(event)
            },
            completion: { [weak self] result in
                guard let self else { return }
                let isCurrent = self.lock.withLock {
                    guard self.services[itemID] === service else { return false }
                    self.services[itemID] = nil
                    return true
                }
                guard isCurrent else { return }
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
