import XCTest
import AVFoundation
@testable import OpenWhisper

final class OpenWhisperTests: XCTestCase {
    func testFrenchLayout() {
        XCTAssertEqual(French.letters.joined(), "azertyuiopqsdfghjklmwxcvbn")
        XCTAssertEqual(Set(French.letters.joined()).count, 26)
        XCTAssertEqual(French.numbers.first, "1234567890")
        XCTAssertTrue(French.symbols.joined().contains("€") || French.numbers.joined().contains("€"))
        XCTAssertTrue(French.accents["e"]!.contains("ê"))
        XCTAssertEqual(French.fragment("l’été"), "été")
        XCTAssertEqual(French.fragment("demain "), "")
        XCTAssertEqual(French.following("Nous "), ["sommes", "avons"])
    }

    func testInboxConsumedOnceAndCleared() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = Inbox(folder: folder)
        try inbox.publish("Un été à Lyon.")
        XCTAssertEqual(try inbox.consume(), "Un été à Lyon.")
        XCTAssertNil(try inbox.consume())
        try inbox.publish("Sortie expirée")
        inbox.discardExpired(now: Date().addingTimeInterval(601))
        XCTAssertNil(try inbox.consume())
        try inbox.publish("Effacer")
        try inbox.clear()
        XCTAssertNil(try inbox.consume())
    }

    func testVoiceGate() {
        XCTAssertFalse(VoiceGate.containsSound(Array(repeating: 0, count: 48000)))
        XCTAssertFalse(VoiceGate.containsSound([1] + Array(repeating: 0, count: 16000)))
        XCTAssertFalse(VoiceGate.containsSound(Array(repeating: 0.1, count: 16000)))
        let quiet = (0..<8000).map { Float(sin(Double($0) * 0.1)) * 0.001 }
        XCTAssertTrue(VoiceGate.containsSound(Array(repeating: 0, count: 8000) + quiet))
    }

    func testDownloadIntegrityProgressAndPreparation() async throws {
        // This test runs in the dedicated simulator test host.
        let model = Model.base
        if model.installed { try FileManager.default.removeItem(at: model.file) }
        let progress = expectation(description: "Réception de données du modèle")
        progress.assertForOverFulfill = false
        let engine = Engine()
        try await engine.install(model) { bytes in if bytes > 0 { progress.fulfill() } }
        defer { try? FileManager.default.removeItem(at: model.file) }
        await fulfillment(of: [progress], timeout: 5)
        XCTAssertTrue(model.installed)
        let bytes = try FileManager.default.attributesOfItem(atPath: model.file.path)[.size] as? NSNumber
        XCTAssertEqual(bytes?.int64Value, model.size)
        await engine.unload()
    }

    func testFrenchInferenceAndSilence() async throws {
        let bundle = Bundle(for: Self.self)
        let model = Model.base
        let fm = FileManager.default
        let fixture = try XCTUnwrap(bundle.url(forResource: model.name, withExtension: nil))
        try fm.createDirectory(at: model.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !model.installed { try fm.copyItem(at: fixture, to: model.file) }
        let engine = Engine()
        try await engine.prepare(model)
        for name in ["court", "long", "silence"] {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let ptr = try XCTUnwrap(buffer.floatChannelData?[0])
            let samples = Array(UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength)))
            if name == "silence" {
                do { _ = try await engine.transcribe(samples, model: model); XCTFail("Le silence doit être rejeté") }
                catch { XCTAssertEqual(error.localizedDescription, "Aucune parole audible.") }
            } else {
                let text = try await engine.transcribe(samples, model: model).lowercased()
                XCTAssertFalse(text.isEmpty)
                if name == "long" { XCTAssertTrue(text.contains("dossier"), text) }
            }
        }
    }
}
