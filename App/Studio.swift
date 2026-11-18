import AVFoundation
import SwiftUI

@MainActor final class Studio: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var model = Model(rawValue: UserDefaults.standard.string(forKey: "model") ?? "") ?? .small
    @Published var working = false
    @Published var recording = false
    @Published var bytes: Int64?
    @Published var note = ""
    @Published var result = ""
    @Published var permission = AVAudioSession.sharedInstance().recordPermission
    let engine = Engine()
    private var recorder: AVAudioRecorder?
    private let scratch = URL.temporaryDirectory.appendingPathComponent("ow-capture.wav")
    private var pauseTimer: Timer?
    private var lastSound: TimeInterval?
    private var attempt = UUID()
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        try? Inbox.shared().discardExpired()
        try? FileManager.default.removeItem(at: scratch)
        let notifications = [AVAudioSession.interruptionNotification, UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                             UIApplication.protectedDataWillBecomeUnavailableNotification, AVAudioSession.mediaServicesWereResetNotification]
        for name in notifications {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            })
        }
    }

    func authorize() {
        AVAudioApplication.requestRecordPermission { _ in
            Task { @MainActor in self.permission = AVAudioSession.sharedInstance().recordPermission }
        }
    }
    func select(_ choice: Model) {
        guard !working, !recording else { return }
        model = choice
        UserDefaults.standard.set(choice.rawValue, forKey: "model")
        note = ""
    }
    func install() async {
        guard !working, !recording, !model.installed else { return }
        working = true
        bytes = 0
        note = "Téléchargement puis vérification du modèle…"
        defer { working = false; bytes = nil }
        do {
            try await engine.install(model) { amount in
                Task { @MainActor in if self.bytes != nil { self.bytes = amount } }
            }
            note = "Modèle vérifié et chargé."
        } catch { note = error.localizedDescription }
    }
    func remove() async {
        guard !working, !recording else { return }
        working = true
        defer { working = false }
        await engine.unload()
        do { try FileManager.default.removeItem(at: model.file); note = "Modèle supprimé." }
        catch { note = error.localizedDescription }
    }
    func start() {
        guard !working, !recording else { return }
        guard model.installed else { note = "Installez le modèle dans Modèles IA."; return }
        guard permission == .granted else { note = "Autorisez le microphone dans les réglages."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let capture = try AVAudioRecorder(url: scratch, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            recorder = capture
            guard capture.prepareToRecord() else { throw Message("Impossible de préparer le fichier audio.") }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: scratch.path)
            capture.delegate = self
            guard capture.record(forDuration: 120) else { throw Message("Le microphone est indisponible.") }
            recording = true
            if Settings.defaults().bool(forKey: "finSurPause") {
                capture.isMeteringEnabled = true
                lastSound = nil
                pauseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkPause() }
                }
            }
            note = "Enregistrement · glissez vers la gauche pour annuler."
            feedback()
        } catch { releaseAudio(); note = error.localizedDescription }
    }

    private func feedback() {
        if Settings.defaults().bool(forKey: "haptique") { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
    private func checkPause() {
        guard recording, let recorder else { return }
        recorder.updateMeters()
        if recorder.averagePower(forChannel: 0) > -43 { lastSound = recorder.currentTime }
        else if let lastSound, recorder.currentTime - lastSound >= 2 { finish() }
    }
    private func releaseAudio() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        lastSound = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? FileManager.default.removeItem(at: scratch)
    }
    func cancel() {
        attempt = UUID()
        if recording { releaseAudio(); note = "Dictée annulée."; feedback() }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            if flag { self.finish() } else { self.cancel(); self.note = "Enregistrement interrompu." }
        }
    }
    func finish() {
        guard recording else { return }
        recorder?.delegate = nil
        recorder?.stop()
        feedback()
        let samples: [Float]
        do {
            let file = try AVAudioFile(forReading: scratch, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard file.length >= 6400, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)) else { throw Message("Dictée trop courte.") }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else { throw Message("Format audio indisponible.") }
            samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        } catch { releaseAudio(); note = error.localizedDescription; return }
        releaseAudio()
        working = true
        note = "Transcription sur cet iPhone…"
        let id = UUID()
        attempt = id
        Task {
            defer { working = false }
            do {
                let text = try await engine.transcribe(samples, model: model)
                guard attempt == id else { note = "Transcription annulée."; return }
                result = Settings.defaults().bool(forKey: "ponctuation") ? text :
                    text.filter { !".,;:!?…".contains($0) }
                note = "Dictée prête."
            } catch { note = error.localizedDescription }
        }
    }
    func share() {
        do { try Inbox.shared().publish(result); note = "Retournez dans votre application et touchez le micro du clavier pour insérer." }
        catch { note = error.localizedDescription }
    }
    func clear() {
        cancel()
        result = ""
        try? FileManager.default.removeItem(at: scratch)
        do { try Inbox.shared().clear(); note = "Dictées effacées." } catch { note = error.localizedDescription }
    }
}
