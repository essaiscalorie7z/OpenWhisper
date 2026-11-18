import Foundation
import CryptoKit

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Int64) -> Void
    init(_ report: @escaping @Sendable (Int64) -> Void) { self.report = report }
    private var completion: CheckedContinuation<URL, Error>?
    private var received: Result<URL, Error>?

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        received = Result {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Message("Téléchargement refusé. Réessayez.")
            }
            let staging = URL.temporaryDirectory.appendingPathComponent("ow-modele-" + UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: staging)
            return staging
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { completion = nil; session.finishTasksAndInvalidate() }
        if let error {
            if case let .success(url)? = received { try? FileManager.default.removeItem(at: url) }
            completion?.resume(throwing: error)
        } else {
            completion?.resume(with: received ?? .failure(Message("Fichier de modèle indisponible.")))
        }
    }
}

extension Engine {
    func install(_ model: Model, report: @escaping @Sendable (Int64) -> Void) async throws {
        let fm = FileManager.default
        var directory = model.file.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var attrs = URLResourceValues()
        attrs.isExcludedFromBackup = true
        try directory.setResourceValues(attrs)
        if let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < model.size + 16_000_000 { throw Message("Espace libre insuffisant pour ce modèle.") }
        let tmp = try await ProgressDelegate(report).download(model.remote)
        defer { try? fm.removeItem(at: tmp) }
        let handle = try FileHandle(forReadingFrom: tmp)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == model.digest else {
            throw Message("Le fichier reçu a échoué au contrôle SHA-256. Réessayez.")
        }
        try fm.moveItem(at: tmp, to: model.file)
        do { try prepare(model) } catch { try? fm.removeItem(at: model.file); throw error }
    }
}
