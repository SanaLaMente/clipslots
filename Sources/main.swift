// ClipSlots — diez portapapeles numerados para macOS.
//
//   ⌘C + N   con ⌘ y C apretados, tocás un número: guarda lo copiado en el slot N.
//   ⌘V + N   con ⌘ y V apretados, tocás un número: pega el slot N y deja tu
//            portapapeles como estaba.
//
// Los slots viven en ~/Library/Application Support/ClipSlots/slots.json.

import AppKit
import Carbon.HIToolbox

extension NSPasteboard.PasteboardType {
    /// Marca que usan los gestores de contraseñas (nspasteboard.org) para pedir
    /// que nadie guarde lo que copiaron.
    static let concealed = Self("org.nspasteboard.ConcealedType")
}

// MARK: - Almacenamiento

/// Guarda los diez slots en un JSON local que solo tu usuario puede leer.
final class SlotStore {
    static let order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

    let directory: URL
    private let file: URL
    private var slots: [String: String]

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipSlots", isDirectory: true)
        file = directory.appendingPathComponent("slots.json")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        slots = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
    }

    subscript(slot: Int) -> String? { slots[String(slot)] }

    func set(_ text: String, for slot: Int) {
        slots[String(slot)] = text
        save()
    }

    func clear() {
        slots.removeAll()
        save()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(slots).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            NSLog("ClipSlots: no pude guardar los slots: \(error)")
        }
    }
}

// MARK: - Teclado

private let digitSlots: [Int64: Int] = [
    Int64(kVK_ANSI_1): 1, Int64(kVK_ANSI_2): 2, Int64(kVK_ANSI_3): 3, Int64(kVK_ANSI_4): 4,
    Int64(kVK_ANSI_5): 5, Int64(kVK_ANSI_6): 6, Int64(kVK_ANSI_7): 7, Int64(kVK_ANSI_8): 8,
    Int64(kVK_ANSI_9): 9, Int64(kVK_ANSI_0): 0,
]
private let keyC = Int64(kVK_ANSI_C)
private let keyV = Int64(kVK_ANSI_V)

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
    return monitor.handle(type, event)
}

/// Escucha el teclado de todo el sistema con un event tap y resuelve los
/// atajos ⌘C + N y ⌘V + N. Todo lo demás pasa sin tocarse.
final class KeyMonitor {
    /// Firma de los eventos que posteamos nosotros, para no procesarlos dos veces.
    private static let marker: Int64 = 0x434C_5053  // "CLPS"

    private let store: SlotStore
    private var tap: CFMachPort?

    /// ⌘C está apretado: un número ahora guarda en un slot.
    private var copyArmed = false
    /// changeCount del portapapeles antes de que la app procesara el ⌘C.
    private var changeCountBeforeCopy = 0
    /// ⌘V está apretado y retenido: decidimos qué pegar al soltar V.
    private var pasteArmed = false
    private var pastedSlot = false
    /// Números que nos tragamos al bajar; también nos tragamos su keyUp.
    private var swallowedKeyUps = Set<Int64>()

    var onSave: ((Int) -> Void)?
    var isRunning: Bool { tap != nil }

    init(store: SlotStore) {
        self.store = store
    }

    /// Crea el event tap. Devuelve false si macOS todavía no dio el permiso de Accesibilidad.
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // macOS apaga el tap si tardamos o si el usuario lo pide; lo reactivamos limpio.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            copyArmed = false
            pasteArmed = false
            swallowedKeyUps.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return pass }

        let key = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp {
            if key == keyC { copyArmed = false }
            if key == keyV && pasteArmed {
                pasteArmed = false
                // Soltaste V sin tocar un número: era un ⌘V común.
                if !pastedSlot { postCommandV() }
                return nil
            }
            return swallowedKeyUps.remove(key) != nil ? nil : pass
        }

        guard type == .keyDown else { return pass }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let onlyCommand =
            event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand

        if key == keyC && onlyCommand && !isRepeat {
            // Dejamos pasar ⌘C: la app copia como siempre.
            copyArmed = true
            changeCountBeforeCopy = NSPasteboard.general.changeCount
            return pass
        }

        if key == keyV && (onlyCommand || pasteArmed) {
            // Retenemos ⌘V (y su autorepeat) hasta saber si viene un número.
            if !isRepeat {
                pasteArmed = true
                pastedSlot = false
            }
            return pasteArmed ? nil : pass
        }

        if let slot = digitSlots[key], onlyCommand, copyArmed || pasteArmed {
            swallowedKeyUps.insert(key)
            if isRepeat { return nil }
            if pasteArmed {
                pastedSlot = true
                DispatchQueue.main.async { self.paste(slot) }
            } else {
                let before = changeCountBeforeCopy
                DispatchQueue.main.async { self.save(slot, changeCountBefore: before) }
            }
            return nil
        }

        return pass
    }

    /// Espera a que la app termine de copiar (hasta medio segundo) y guarda el texto.
    private func save(_ slot: Int, changeCountBefore: Int, attempt: Int = 0) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == changeCountBefore && attempt < 25 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.save(slot, changeCountBefore: changeCountBefore, attempt: attempt + 1)
            }
            return
        }
        guard pasteboard.types?.contains(.concealed) != true,
            let text = pasteboard.string(forType: .string), !text.isEmpty
        else {
            NSSound.beep()
            return
        }
        store.set(text, for: slot)
        onSave?(slot)
    }

    /// Pone el slot en el portapapeles, simula ⌘V y después devuelve lo que había.
    private func paste(_ slot: Int) {
        guard let text = store[slot] else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        let backup: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount
        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Si alguien copió algo mientras tanto, no lo pisamos.
            guard pasteboard.changeCount == ours else { return }
            pasteboard.clearContents()
            if !backup.isEmpty { pasteboard.writeObjects(backup) }
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
            else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

// MARK: - Barra de menú

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SlotStore()
    private lazy var monitor = KeyMonitor(store: store)
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        monitor.onSave = { [weak self] _ in self?.flashSaved() }
        startMonitor()
    }

    private func startMonitor() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt), monitor.start() {
            showIcon("list.number")
            return
        }
        // Sin permiso todavía: lo reintentamos hasta que lo actives en Ajustes.
        showIcon("exclamationmark.triangle")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.monitor.start() else { return }
            timer.invalidate()
            self.showIcon("list.number")
        }
    }

    private func showIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClipSlots")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func flashSaved() {
        showIcon("checkmark")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showIcon("list.number") }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = monitor.isRunning ? "⌘C + N guarda  ·  ⌘V + N pega" : "Falta el permiso de Accesibilidad"
        menu.addItem(withTitle: header, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        for slot in SlotStore.order {
            let text = store[slot]
            let item = NSMenuItem(
                title: "\(slot)   \(text.map(Self.preview) ?? "vacío")", action: #selector(copySlot(_:)),
                keyEquivalent: "")
            item.target = self
            item.tag = slot
            item.isEnabled = text != nil
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !monitor.isRunning {
            addItem(to: menu, "Abrir ajustes de Accesibilidad…", #selector(openAccessibilitySettings))
        }
        addItem(to: menu, "Mostrar carpeta de datos", #selector(revealData))
        addItem(to: menu, "Vaciar todos los slots", #selector(clearSlots))
        menu.addItem(.separator())
        addItem(to: menu, "Salir de ClipSlots", #selector(quit), key: "q")
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private static func preview(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return line.count > 40 ? line.prefix(40) + "…" : line
    }

    /// Click en un slot: lo copia al portapapeles normal.
    @objc private func copySlot(_ sender: NSMenuItem) {
        guard let text = store[sender.tag] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func revealData() {
        NSWorkspace.shared.open(store.directory)
    }

    @objc private func clearSlots() {
        store.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
