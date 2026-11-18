import Foundation
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
    var file: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name) }
    var installed: Bool { FileManager.default.fileExists(atPath: file.path) }
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
        var candidate = whisper_init_from_file_with_params(model.file.path, options)
        if candidate == nil && options.use_gpu {
            options.use_gpu = false
            candidate = whisper_init_from_file_with_params(model.file.path, options)
        }
        guard let ctx = candidate else {
            throw Message("Chargement impossible. Essayez le modèle Base ou réinstallez le modèle.")
        }
        context = ctx
        loaded = model
    }
    func transcribe(_ samples: [Float], model: Model) throws -> String {
        guard samples.count >= 6400, VoiceGate.containsSound(samples) else { throw Message("Aucune parole audible.") }
        try prepare(model)
        var p = whisper_full_default_params(model == .small ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)
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
        var energies: [Float] = []
        energies.reserveCapacity(samples.count / 320 + 1)
        for start in stride(from: 0, to: samples.count, by: 320) {
            let frame = samples[start..<min(start + 320, samples.count)]
            var sum: Float = 0
            var sumSquares: Float = 0
            for sample in frame {
                sum += sample
                sumSquares += sample * sample
            }
            let count = Float(frame.count)
            let mean = sum / count
            energies.append(max(0, sumSquares / count - mean * mean))
        }
        guard energies.count >= 6 else { return false }
        energies.sort()
        let floor = energies[energies.count / 10]
        let threshold = max(0.000000025, min(0.000012, floor * 3))
        return energies[energies.count - 6] > threshold
    }
}
