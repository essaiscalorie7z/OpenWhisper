import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@main struct OpenWhisperApp: App {
    @StateObject private var studio = Studio()
    var body: some Scene {
        WindowGroup { Home().environmentObject(studio).environment(\.locale, Locale(identifier: "fr_FR")) }
    }
}

struct Home: View {
    @EnvironmentObject var studio: Studio
    @AppStorage("configure") private var configured = false
    @State private var wizard = false
    @Environment(\.scenePhase) private var phase
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            List {
                Section("Sur cet iPhone") {
                    LabeledContent("Modèle", value: studio.model.installed ? studio.model.title : "À télécharger")
                    LabeledContent("Microphone", value: studio.permission == .granted ? "Autorisé" : studio.permission == .denied ? "Refusé" : "À autoriser")
                    if let seen = Settings.defaults().object(forKey: "derniereActivation") as? Date {
                        LabeledContent("Clavier utilisé", value: seen.formatted(date: .abbreviated, time: .shortened))
                    } else { Text("Activation du clavier à vérifier dans Réglages.") }
                    NavigationLink("Dicter en français") { DictationPage() }
                }
                Section {
                    NavigationLink("Modèles IA") { Form { ModelSection() }.navigationTitle("Modèles IA") }
                    NavigationLink("Réglages du clavier") { PreferencesPage() }
                    NavigationLink("Réglages vocaux") { Form { VoiceOptions() }.navigationTitle("Voix") }
                    Button("Assistant de configuration") { wizard = true }
                }
                Section("Confidentialité") {
                    Text("Seul le téléchargement des modèles nécessite Internet. La voix est traitée sur cet iPhone. Le clavier ne conserve pas vos frappes.")
                    Text("« Envoyer au clavier » rend une dictée récupérable pendant dix minutes. Elle est supprimée à la lecture. Une dictée abandonnée peut être effacée ici.")
                    Button("Effacer les dictées", role: .destructive) { confirmClear = true }
                }
                if !studio.note.isEmpty { Text(studio.note) }
            }
            .navigationTitle("Open Whisper")
            .onAppear { if !configured { wizard = true } }
            .onChange(of: phase) { _, value in
                if value == .active { studio.permission = AVAudioSession.sharedInstance().recordPermission }
            }
            .sheet(isPresented: $wizard) { Wizard { configured = true; wizard = false } }
            .confirmationDialog("Effacer le texte et les dictées partagées ?", isPresented: $confirmClear) {
                Button("Effacer", role: .destructive) { studio.clear() }
            }
        }
    }
}

struct ModelSection: View {
    @EnvironmentObject var studio: Studio
    @State private var confirm = false
    var body: some View {
        Section("Whisper multilingue · français") {
            Picker("Modèle", selection: Binding(get: { studio.model }, set: { studio.select($0) })) {
                ForEach(Model.allCases) { Text($0.title).tag($0) }
            }.disabled(studio.working || studio.recording)
            Text(studio.model == .small ? "Small privilégie la précision. Base réduit la mémoire et le temps de calcul." : "Base convient aux appareils disposant de moins de mémoire.")
            LabeledContent("Téléchargement", value: studio.model.size.formatted(.byteCount(style: .file)))
            LabeledContent("Espace libre demandé", value: (studio.model.size + 16_000_000).formatted(.byteCount(style: .file)))
            if let bytes = studio.bytes {
                ProgressView(value: Double(min(bytes, studio.model.size)), total: Double(studio.model.size))
                Text(bytes.formatted(.byteCount(style: .file)) + " reçus")
            }
            if studio.model.installed {
                LabeledContent("Espace occupé", value: Int64((try? studio.model.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0).formatted(.byteCount(style: .file)))
                Button("Supprimer ce modèle", role: .destructive) { confirm = true }
                    .disabled(studio.working || studio.recording)
            } else {
                Button("Télécharger le modèle") { Task { await studio.install() } }.disabled(studio.working || studio.recording)
            }
            if !studio.note.isEmpty { Text(studio.note).font(.footnote) }
        }
        .confirmationDialog("Supprimer ce modèle de l’iPhone ?", isPresented: $confirm) {
            Button("Supprimer", role: .destructive) { Task { await studio.remove() } }
        }
    }
}

struct MicrophoneSection: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.openURL) var openURL
    var body: some View {
        Section("Microphone de l’application") {
            Text("Le microphone s’active pendant votre dictée au premier plan.")
            if studio.permission == .denied {
                Button("Ouvrir les réglages d’Open Whisper") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            } else if studio.permission == .granted { Label("Microphone autorisé", systemImage: "checkmark.circle") }
            else { Button("Autoriser le microphone") { studio.authorize() } }
        }
    }
}

struct VoiceOptions: View {
    @AppStorage("ponctuation", store: Settings.defaults()) var punctuation = true
    var body: some View {
        Section("Transcription") {
            LabeledContent("Langue", value: "Français")
            Toggle("Conserver la ponctuation", isOn: $punctuation)
            Text("Une pause conserve l’enregistrement en cours. Relâchez pour terminer. Durée maximale par dictée : deux minutes.")
        }
        MicrophoneSection()
    }
}

struct PreferencesPage: View {
    @AppStorage("suggestions", store: Settings.defaults()) var suggestions = true
    @AppStorage("correction", store: Settings.defaults()) var correction = true
    @AppStorage("haptique", store: Settings.defaults()) var haptic = true
    @AppStorage("apparence", store: Settings.defaults()) var appearance = "Automatique"
    var body: some View {
        Form {
            Toggle("Suggestions françaises", isOn: $suggestions)
            Toggle("Corriger au passage à l’espace", isOn: $correction)
            Toggle("Retour haptique", isOn: $haptic)
            Picker("Apparence", selection: $appearance) {
                ForEach(["Automatique", "Clair", "Sombre"], id: \.self) { Text($0) }
            }
            Text("L’accès complet permet au clavier de lire ces préférences partagées. Sans lui, le clavier emploie ses réglages par défaut.")
        }.navigationTitle("Clavier")
    }
}

struct DictationPage: View {
    @EnvironmentObject var studio: Studio
    @State private var touching = false
    @State private var cancelled = false
    @State private var sample = ""
    var body: some View {
        Form {
            if !studio.model.installed { ModelSection() }
            if studio.permission != .granted { MicrophoneSection() }
            Section("Dictée locale") {
                Label(studio.recording ? "Enregistrement en cours" : "Maintenir pour parler",
                      systemImage: studio.recording ? "waveform" : "mic.fill")
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 62)
                    .background(studio.recording ? Color.red : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                        if !touching { touching = true; cancelled = false; studio.start() }
                        if drag.translation.width < -65 && !cancelled { cancelled = true; studio.cancel() }
                    }.onEnded { _ in touching = false; if !cancelled { studio.finish() } })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if studio.recording { studio.finish() } else { studio.start() } }
                    .disabled(studio.working || !studio.model.installed || studio.permission != .granted)
                if !studio.note.isEmpty { Text(studio.note).font(.footnote) }
            }
            if !studio.result.isEmpty {
                Section("Transcription") {
                    Text(studio.result).textSelection(.enabled)
                    Button("Envoyer au clavier") { studio.share() }
                    Button("Copier") {
                        UIPasteboard.general.setItems([[UTType.plainText.identifier: studio.result]],
                            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
                        studio.note = "Copié sur cet iPhone."
                    }
                }
            }
            Section("Essayer le clavier") {
                TextField("Écrivez ici", text: $sample, axis: .vertical)
                Text("Sélectionnez Open Whisper avec le globe. Pour tester hors ligne, activez le mode Avion après l’installation du modèle.")
            }
        }.navigationTitle("Dicter").onDisappear { if studio.recording { studio.cancel() } }
    }
}

struct Wizard: View {
    let done: () -> Void
    @State private var step = 0
    let titles = ["Bienvenue", "Modèle vocal", "Microphone", "Activer le clavier", "Dicter et insérer", "Premier essai"]
    var body: some View {
        NavigationStack {
            VStack {
                if step == 5 { DictationPage() }
                else {
                    Form {
                        switch step {
                        case 0: Text("Open Whisper vous permet d’écrire en AZERTY et de dicter en français. Après le téléchargement du modèle, la reconnaissance fonctionne sur votre iPhone, même hors ligne.")
                        case 1: ModelSection()
                        case 2: MicrophoneSection()
                        case 3:
                            Text("Ouvrez Réglages → Général → Clavier → Claviers → Ajouter un clavier, puis choisissez Open Whisper.")
                            Text("Pour transférer vos dictées, ouvrez ensuite la fiche Open Whisper et autorisez l’accès complet. Cette autorisation sert au conteneur partagé. Le clavier ne peut pas enregistrer.")
                        default:
                            Text("Dans Open Whisper, maintenez le microphone puis relâchez. Touchez « Envoyer au clavier ». Revenez dans votre application, sélectionnez le clavier Open Whisper puis touchez son microphone pour insérer la dictée.")
                            Text("Vous pouvez aussi copier le résultat et utiliser la commande Coller d’iOS.")
                        }
                    }
                }
                HStack {
                    if step > 0 { Button("Précédent") { step -= 1 } }
                    Spacer()
                    Text("\(step + 1) / 6").foregroundStyle(.secondary)
                    Spacer()
                    Button(step == 5 ? "Terminer" : "Suivant") { if step == 5 { done() } else { step += 1 } }
                }.padding()
            }.navigationTitle(titles[step])
        }.interactiveDismissDisabled()
    }
}
