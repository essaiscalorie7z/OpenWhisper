import UIKit

class KeyboardController: UIInputViewController {
    enum Mode { case letters, numbers, symbols, emoji }
    enum Shift { case off, once, locked }
    private var mode = Mode.letters
    private var shift = Shift.off
    private var lastShift = Date.distantPast
    private let column = UIStackView()
    private var height: NSLayoutConstraint?
    private let checker = UITextChecker()
    private var choices: [UIButton] = []
    private var pendingSpace = false
    private var category = 0
    private var lastKeyboardType: UIKeyboardType?
    private var eraseTimer: Timer?
    private var instruction: String?
    private let categories = ["Visages", "Gestes", "Nature", "Objets"]
    private let emoji = ["😀😃😄😁😅😂🤣😊🥰😍😘😎🤔😢😭😡🥳🤩",
                        "👋🤚✋👌✌️🤞🤟👍👎👏🙌🫶💪🤝🙏👀❤️💙",
                        "🌷🌻🌹🌱🌳🍀🐱🐶🐼🦊🐝🐬☀️🌙⭐🌈🔥💧",
                        "🎁🎉🎂🎈🎵🎸📱💡📚✏️📷🔑🏠🚲🚗🚆✈️⌚️"]
    private var prefs: UserDefaults { Settings.defaults(shared: hasFullAccess) }
    private var dark: Bool { traitCollection.userInterfaceStyle == .dark }
    private var isCompact: Bool { view.bounds.width > 540 }

    override func viewDidLoad() {
        super.viewDidLoad()
        column.axis = .vertical
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)])
        let constraint = view.heightAnchor.constraint(equalToConstant: 258)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        height = constraint
        render()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if hasFullAccess { prefs.set(Date(), forKey: "derniereActivation") }
        setModeForField()
        adjustShift()
        render()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        height?.constant = isCompact ? 190 : 258
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRepeat()
        pendingSpace = false
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded, traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { render() }
    }
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if isViewLoaded {
            pendingSpace = false
            if lastKeyboardType != (textDocumentProxy.keyboardType ?? .default) { setModeForField() }
            adjustShift(); render()
        }
    }
    private func setModeForField() {
        let type = textDocumentProxy.keyboardType ?? .default
        lastKeyboardType = type
        mode = [.numberPad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad].contains(type) ? .numbers : .letters
    }
    private var before: String { textDocumentProxy.documentContextBeforeInput ?? "" }
    private var after: String { textDocumentProxy.documentContextAfterInput ?? "" }
    private var word: String { French.fragment(before) }
    private var writingWords: Bool {
        ![UIKeyboardType.emailAddress, .URL, .asciiCapable, .numberPad, .decimalPad].contains(textDocumentProxy.keyboardType ?? .default)
    }
    private func adjustShift() {
        guard shift != .locked else { return }
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .allCharacters: shift = .locked
        case .words: shift = before.isEmpty || before.last?.isWhitespace == true ? .once : .off
        case .sentences:
            let prefix = before.trimmingCharacters(in: .whitespaces)
            shift = writingWords && (prefix.isEmpty || before.last == "\n" || (before.last == " " && ".!?".contains(prefix.last ?? " "))) ? .once : .off
        default: shift = .off
        }
    }
    private func key(_ label: String, special: Bool = false, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: label.count == 1 ? 23 : 15)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.setTitleColor(dark ? .white : .black, for: .normal)
        button.backgroundColor = UIColor(white: dark ? (special ? 0.26 : 0.40) : (special ? 0.68 : 1), alpha: 1)
        button.layer.cornerRadius = 5
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.34
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    private func row(_ buttons: [UIButton], weights: [CGFloat]? = nil) {
        let strip = UIStackView(arrangedSubviews: buttons)
        strip.spacing = 4
        strip.distribution = weights == nil ? .fillEqually : .fill
        if let weights, let first = buttons.first {
            for i in 1..<buttons.count {
                buttons[i].widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: weights[i]/weights[0]).isActive = true
            }
        }
        column.addArrangedSubview(strip)
    }
    private func render() {
        let style = prefs.string(forKey: "apparence")
        let appearance: UIUserInterfaceStyle = style == "Sombre" ? .dark : style == "Clair" ? .light :
            (textDocumentProxy.keyboardAppearance == .dark ? .dark : .unspecified)
        if overrideUserInterfaceStyle != appearance { overrideUserInterfaceStyle = appearance }
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        column.distribution = .fillEqually
        view.backgroundColor = UIColor(white: dark ? 0.15 : 0.81, alpha: 1)
        choices = (0..<2).map { i in key("") { [weak self] in self?.accept(i) } }
        let mic = key("") { [weak self] in self?.receive() }
        mic.setImage(UIImage(systemName: "mic"), for: .normal)
        mic.accessibilityLabel = "Récupérer une dictée Open Whisper"
        row(choices + [mic])
        for b in choices + [mic] { b.backgroundColor = .clear; b.layer.shadowOpacity = 0 }
        if let instruction {
            let dismiss = key(instruction) { [weak self] in self?.instruction = nil; self?.render() }
            dismiss.titleLabel?.numberOfLines = 2
            row([dismiss])
        }
        if mode == .emoji {
            row(categories.enumerated().map { i, title in key(i == category ? "• " + title : title) { [weak self] in self?.category = i; self?.render() } })
            let group = Array(emoji[category])
            for section in [Array(group.prefix(9)), Array(group.dropFirst(9))] { row(section.map { characterKey(String($0)) }) }
        } else {
            let layout = mode == .letters ? French.letters : (mode == .numbers ? French.numbers : French.symbols)
            for (i, line) in layout.enumerated() {
                var buttons = line.map { characterKey(shift != .off && mode == .letters ? String($0).uppercased() : String($0)) }
                if i == 2 {
                    if mode == .letters { buttons.append(characterKey("’")) }
                    let toggle = mode == .letters ? (shift == .locked ? "⇪" : "⇧") : (mode == .numbers ? "#+=" : "123")
                    buttons.insert(key(toggle, special: true) { [weak self] in self?.toggleShift() }, at: 0)
                    buttons.append(deletionKey())
                }
                if i == 2 {
                    let widths: [CGFloat] = [1.4] + Array(repeating: 1, count: buttons.count - 2) + [1.4]
                    row(buttons, weights: widths)
                } else { row(buttons) }
            }
        }
        var bottom = [key(mode == .letters ? "123" : "ABC", special: true) { [weak self] in
            guard let self else { return }; mode = mode == .letters ? .numbers : .letters; render()
        }]
        var weights: [CGFloat] = [1.25]
        if needsInputModeSwitchKey {
            let globe = UIButton(type: .system)
            globe.setImage(UIImage(systemName: "globe"), for: .normal)
            globe.accessibilityLabel = "Clavier suivant"
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            bottom.append(globe); weights.append(1)
        }
        bottom.append(key(mode == .emoji ? "abc" : "☺", special: true) { [weak self] in
            guard let self else { return }; mode = mode == .emoji ? .letters : .emoji; render()
        }); weights.append(1)
        if textDocumentProxy.keyboardType == .emailAddress || textDocumentProxy.keyboardType == .URL {
            bottom.append(characterKey(textDocumentProxy.keyboardType == .URL ? "/" : "@")); weights.append(1)
        }
        bottom.append(key("espace") { [weak self] in self?.type(" ") }); weights.append(5)
        if mode == .emoji { bottom.append(deletionKey()); weights.append(1) }
        let returns: [UIReturnKeyType: String] = [.go:"aller", .search:"rechercher", .send:"envoyer", .done:"terminé", .next:"suivant"]
        bottom.append(key(returns[textDocumentProxy.returnKeyType ?? .default] ?? "retour", special: true) { [weak self] in self?.type("\n") })
        weights.append(1.8)
        row(bottom, weights: weights)
        refresh()
    }
    private func characterKey(_ label: String) -> UIButton {
        let button = key(label) { [weak self] in self?.type(label) }
        if mode == .letters, let accents = French.accents[label.lowercased()] {
            button.menu = UIMenu(children: accents.map { char in
                let value = shift == .off ? String(char) : String(char).uppercased()
                return UIAction(title: value) { [weak self] _ in self?.type(value) }
            })
        }
        return button
    }
    private func toggleShift() {
        if mode == .letters {
            if shift != .locked && Date().timeIntervalSince(lastShift) < 0.4 { shift = .locked }
            else { shift = shift == .off ? .once : .off }
            lastShift = Date()
        } else { mode = mode == .numbers ? .symbols : .numbers }
        render()
    }
    private func deletionKey() -> UIButton {
        let button = key("⌫", special: true) { [weak self] in self?.erase() }
        button.accessibilityLabel = "Supprimer"
        button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(heldDelete(_:))))
        return button
    }
    @objc private func heldDelete(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            stopRepeat(); erase()
            eraseTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in self?.erase() }
        } else if [.ended, .cancelled, .failed].contains(gesture.state) { stopRepeat() }
    }
    private func stopRepeat() { eraseTimer?.invalidate(); eraseTimer = nil }
    private func erase() { pendingSpace = false; textDocumentProxy.deleteBackward(); refresh() }

    private func alternatives() -> [String] {
        guard prefs.bool(forKey: "suggestions"), writingWords, mode == .letters else { return [] }
        let token = word
        if token.isEmpty { return French.following(before) }
        let range = NSRange(location: 0, length: token.utf16.count)
        let candidates = (checker.completions(forPartialWordRange: range, in: token, language: "fr_FR") ?? [])
            + (checker.guesses(forWordRange: range, in: token, language: "fr_FR") ?? [])
        var seen = Set<String>()
        let fixes = French.corrections[token].map { [$0] } ?? []
        let local = FrequencyLexicon.bundled.completions(token)
        let ranked = fixes + candidates + local
        return Array((ranked + French.localCompletions(token) + [token]).filter { seen.insert($0).inserted }.prefix(2))
    }
    private var proposed: [String] = []
    private var proposedContext = ""
    private func refresh() {
        proposedContext = before
        proposed = alternatives()
        for (i, b) in choices.enumerated() {
            b.setTitle(i < proposed.count ? proposed[i] : "", for: .normal)
            b.isEnabled = i < proposed.count && (textDocumentProxy.selectedText ?? "").isEmpty && after.first?.isLetter != true
        }
    }
    private func replaceWord(with value: String) {
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(value)
    }
    private func accept(_ i: Int) {
        guard before == proposedContext, i < proposed.count, (textDocumentProxy.selectedText ?? "").isEmpty, after.first?.isLetter != true else { refresh(); return }
        replaceWord(with: proposed[i])
        if after.isEmpty || after.first?.isLetter == true { textDocumentProxy.insertText(" "); pendingSpace = true }
        adjustShift(); render()
    }
    private func type(_ text: String) {
        if prefs.bool(forKey: "haptique") { UISelectionFeedbackGenerator().selectionChanged() }
        if pendingSpace, before.hasSuffix(" "), [".", ",", "’", "\n"].contains(text) { textDocumentProxy.deleteBackward() }
        pendingSpace = false
        if text == " ", writingWords, prefs.bool(forKey: "correction"), textDocumentProxy.autocorrectionType != .no,
           after.first?.isLetter != true {
            let token = word
            let range = NSRange(location: 0, length: token.utf16.count)
            if let known = French.corrections[token] {
                replaceWord(with: known)
            } else if token.count > 2, token == token.lowercased(),
               checker.rangeOfMisspelledWord(in: token, range: range, startingAt: 0, wrap: false, language: "fr_FR").location != NSNotFound,
               let first = checker.guesses(forWordRange: range, in: token, language: "fr_FR")?.first {
                replaceWord(with: first)
            }
        }
        if writingWords && ["!", "?", ";", ":"].contains(text) && mode != .emoji {
            let prefix = before
            if prefix.last == " " { textDocumentProxy.deleteBackward() }
            let previous = prefix.last == " " ? prefix.dropLast().last : prefix.last
            if previous?.isLetter == true {
                textDocumentProxy.insertText(text == ":" ? " " : " ")
            }
        }
        textDocumentProxy.insertText(text)
        if text == " " && mode != .emoji { mode = .letters }
        if shift == .once { shift = .off }
        adjustShift(); render()
    }
    private func receive() {
        guard hasFullAccess else { instruction = "Dictez dans Open Whisper, puis copiez et collez, ou autorisez l’accès complet."; render(); return }
        do {
            if let text = try Inbox.shared().consume() {
                textDocumentProxy.insertText(text)
                instruction = nil
            } else { instruction = "Ouvrez Open Whisper, dictez, puis touchez « Envoyer au clavier »." }
        } catch { instruction = "Lecture impossible. Vérifiez l’accès complet et le partage." }
        render()
    }
}
