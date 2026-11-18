import Foundation
import CryptoKit
import whisper

struct Message: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Model: String, CaseIterable, Identifiable {
    case small, base
    var id: Self { self }
    var title: String { self == .small ? "Small · précision" : "Base · rapidité" }
    var size: Int64 { self == .small ? 190_085_487 : 59_707_625 }
    var digest: String {
        self == .small ? "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb" :
            "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
    }
    var name: String { "ggml-" + rawValue + "-q5_1.bin" }
    var remote: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/" + name)!
    }
    var file: URL { URL.applicationSupportDirectory.appendingPathComponent(name) }
    var installed: Bool { FileManager.default.fileExists(atPath: file.path) }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Int64) -> Void
    init(_ report: @escaping @Sendable (Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

actor Engine {
    private var context: OpaquePointer?
    private var loaded: Model?
    func unload() {
        if let context { whisper_free(context) }
        context = nil
        loaded = nil
    }
    func prepare(_ model: Model) throws {
        if loaded == model, context != nil { return }
        unload()
        var options = whisper_context_default_params()
        #if targetEnvironment(simulator)
        options.use_gpu = false
        #endif
        guard let ctx = whisper_init_from_file_with_params(model.file.path, options) else {
            throw Message("Chargement impossible. Essayez le modèle Base ou réinstallez le modèle.")
        }
        context = ctx
        loaded = model
    }
    func install(_ model: Model, report: @escaping @Sendable (Int64) -> Void) async throws {
        let fm = FileManager.default
        var directory = model.file.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var attrs = URLResourceValues()
        attrs.isExcludedFromBackup = true
        try directory.setResourceValues(attrs)
        if let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < model.size + 16_000_000 { throw Message("Espace libre insuffisant pour ce modèle.") }
        let (tmp, response) = try await URLSession.shared.download(for: URLRequest(url: model.remote), delegate: ProgressDelegate(report))
        defer { try? fm.removeItem(at: tmp) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Message("Téléchargement refusé. Réessayez.") }
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

    func transcribe(_ samples: [Float], model: Model) throws -> String {
        guard samples.count >= 6400, VoiceGate.containsSound(samples) else { throw Message("Aucune parole audible.") }
        try prepare(model)
        var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        p.translate = false
        p.no_context = true
        p.print_progress = false
        p.print_realtime = false
        p.print_timestamps = false
        p.suppress_nst = true
        p.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))
        let status = "fr".withCString { lang in
            p.language = lang
            return samples.withUnsafeBufferPointer { whisper_full(context, p, $0.baseAddress, Int32($0.count)) }
        }
        guard status == 0 else { throw Message("Échec de la transcription locale.") }
        var text = ""
        for i in 0..<whisper_full_n_segments(context) {
            if whisper_full_get_segment_no_speech_prob(context, i) < 0.7,
               let segment = whisper_full_get_segment_text(context, i) { text += String(cString: segment) }
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw Message("Aucune parole reconnue.") }
        return clean
    }
}

enum VoiceGate {
    static func containsSound(_ samples: [Float]) -> Bool {
        var audible = 0
        for start in stride(from: 0, to: samples.count, by: 320) {
            let frame = samples[start..<min(start + 320, samples.count)]
            if frame.reduce(Float(0), { $0 + $1 * $1 }) > Float(frame.count) * 0.000012 {
                audible += 1
                if audible >= 6 { return true }
            }
        }
        return false
    }
}
