import XCTest
import UIKit

@MainActor private final class FieldProxy: NSObject, UITextDocumentProxy {
    let field = UITextView()
    var documentContextBeforeInput: String? { field.text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    let documentIdentifier = UUID()
    var hasText: Bool { !(field.text ?? "").isEmpty }
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var keyboardType: UIKeyboardType = .default
    func insertText(_ text: String) { field.text = (field.text ?? "") + text }
    func deleteBackward() { field.text = String((field.text ?? "").dropLast()) }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}

@MainActor private final class HostedKeyboard: KeyboardController {
    let proxy = FieldProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
    override var hasFullAccess: Bool { false }
    override var needsInputModeSwitchKey: Bool { true }

    func buttons(in node: UIView) -> [UIButton] {
        node.subviews.flatMap { child -> [UIButton] in
            if let button = child as? UIButton { return [button] }
            return buttons(in: child)
        }
    }
    func tap(_ title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let button = try XCTUnwrap(buttons(in: view).last { $0.currentTitle == title }, file: file, line: line)
        button.sendActions(for: .touchUpInside)
    }
}

final class KeyboardTests: XCTestCase {
    @MainActor func testTypingModeChangesAndTextInsertion() throws {
        let keyboard = HostedKeyboard()
        keyboard.loadViewIfNeeded()
        keyboard.viewWillAppear(false)
        try keyboard.tap("A")
        try keyboard.tap("z")
        try keyboard.tap("123")
        try keyboard.tap("9")
        try keyboard.tap("#+=")
        try keyboard.tap("#")
        try keyboard.tap("espace")
        try keyboard.tap("☺")
        try keyboard.tap("Nature")
        try keyboard.tap("🐱")
        try keyboard.tap("⌫")
        try keyboard.tap("abc")
        try keyboard.tap("retour")
        XCTAssertEqual(keyboard.proxy.field.text, "Az9# \n")
        XCTAssertTrue(keyboard.buttons(in: keyboard.view).contains { $0.accessibilityLabel == "Clavier suivant" })
    }
    func testBundledFrenchCompletionsWithoutSystemDictionary() {
        XCTAssertEqual(FrequencyLexicon.bundled.completions("ordinat").count, 2)
        XCTAssertTrue(FrequencyLexicon.bundled.completions("ordinat").contains("ordinateur"))
        XCTAssertTrue(FrequencyLexicon.bundled.completions("Écol").allSatisfy { $0.hasPrefix("Écol") || $0.hasPrefix("Ecol") })
    }
    @MainActor func testCorrectionWithoutSystemDictionary() throws {
        let keyboard = HostedKeyboard()
        keyboard.loadViewIfNeeded()
        keyboard.proxy.field.text = "beacoup"
        keyboard.viewWillAppear(false)
        try keyboard.tap("espace")
        XCTAssertEqual(keyboard.proxy.field.text, "beaucoup ")
    }

    @MainActor func testSuggestionsShiftAccentsAndMicrophoneHelp() throws {
        let keyboard = HostedKeyboard()
        keyboard.loadViewIfNeeded()
        keyboard.viewWillAppear(false)
        try keyboard.tap("Bonjour")
        XCTAssertEqual(keyboard.proxy.field.text, "Bonjour ")
        try keyboard.tap("⇧")
        try keyboard.tap("⇧")
        try keyboard.tap("E")
        try keyboard.tap("E")
        XCTAssertEqual(keyboard.proxy.field.text, "Bonjour EE")
        let e = try XCTUnwrap(keyboard.buttons(in: keyboard.view).last { $0.currentTitle == "E" })
        XCTAssertTrue(e.menu?.children.contains { $0.title == "É" } == true)
        let mic = try XCTUnwrap(keyboard.buttons(in: keyboard.view).first { $0.accessibilityLabel == "Récupérer une dictée Open Whisper" })
        mic.sendActions(for: .touchUpInside)
        XCTAssertTrue(keyboard.buttons(in: keyboard.view).contains { $0.currentTitle?.contains("accès complet") == true })
        XCTAssertEqual(keyboard.proxy.field.text, "Bonjour EE")
    }
}
