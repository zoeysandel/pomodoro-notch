import AppKit
import Combine
import PomodoroCore

private struct TimerPreferences: Codable {
    var focusDurationSeconds: Int?
    var focusMinutes: Int?
}

@MainActor final class TimerModel: ObservableObject {
    @Published private(set) var session = Session()
    @Published private(set) var focusDurationSeconds = 1_500
    @Published var now = Date()
    @Published var expanded = true
    @Published var draft = ""
    @Published var isVisible = true
    @Published var keyboardFocusRequest = 0
    @Published private(set) var storageWarning: String?
    var onGeometryChange: (() -> Void)?
    var onStatusChange: (() -> Void)?
    var onQuit: (() -> Void)?
    var onKeyboardFocusRequest: (() -> Void)?
    var onPresentationStatus: (() -> [String: Any])?
    private let stateURL: URL
    private let preferencesURL: URL
    private var ticker: Timer?

    init(directory: URL) {
        stateURL = directory.appendingPathComponent("session.json")
        preferencesURL = directory.appendingPathComponent("preferences.json")
        if let data = try? Data(contentsOf: preferencesURL),
           let saved = try? JSONDecoder().decode(TimerPreferences.self, from: data) {
            if let seconds = saved.focusDurationSeconds, FocusDuration.range.contains(seconds) {
                focusDurationSeconds = seconds
            } else if let minutes = saved.focusMinutes, (1...180).contains(minutes) {
                focusDurationSeconds = minutes * 60
            }
        }
        if let data = try? Data(contentsOf: stateURL),
           let saved = try? JSONDecoder().decode(Session.self, from: data),
           saved.duration.isFinite, saved.duration >= 1, saved.duration <= 10_800,
           saved.remaining.isFinite, saved.remaining >= 0, saved.remaining <= saved.duration,
           saved.phase != .running || saved.deadline != nil {
            session = saved
            draft = saved.task
            if session.advance(to: Date()) { persist() }
            expanded = session.phase == .idle || session.phase == .completed
        }
        prepareIdleDuration()
        ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    var secondsLeft: Double { session.secondsLeft(at: now) }
    var focusMinutes: Int { focusDurationSeconds / 60 }
    var focusClock: String { FocusDuration.clock(focusDurationSeconds) }
    var clock: String {
        let seconds = Int(ceil(secondsLeft))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var progress: Double { min(1, max(0, 1 - secondsLeft / session.duration)) }
    var isActive: Bool { session.phase == .running || session.phase == .paused }
    var isBreak: Bool { session.kind == .rest }
    var label: String {
        switch session.phase {
        case .idle: return "Focus"
        case .paused: return isBreak ? "Break paused" : "Focus paused"
        case .completed: return isBreak ? "Break complete" : "Focus complete"
        case .running: return isBreak ? "Break" : "Focus"
        }
    }

    func tick() {
        now = Date()
        if session.advance(to: now) {
            presentCompletion()
        }
        onStatusChange?()
    }

    private func presentCompletion() {
        expanded = true
        isVisible = true
        persist()
        onGeometryChange?()
        NSSound(named: "Glass")?.play()
    }

    func start(task: String? = nil, seconds: Double? = nil, kind: SessionKind = .focus) {
        let title = task ?? (kind == .rest ? session.task : draft)
        let duration = seconds ?? (kind == .rest ? 300 : Double(focusDurationSeconds))
        session.start(task: title, kind: kind, duration: duration, at: Date())
        draft = session.task
        now = Date()
        expanded = false
        isVisible = true
        persist()
        onGeometryChange?()
        onStatusChange?()
    }

    func pauseOrResume() {
        now = Date()
        if session.phase == .paused { session.resume(at: now) }
        else if session.pause(at: now) { presentCompletion() }
        persist()
        onStatusChange?()
    }

    func updateTask(_ text: String) {
        let clean = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(160))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        session.task = clean
        draft = clean
        persist()
    }

    @discardableResult func updateFocusDuration(seconds: Int) -> Bool {
        guard session.phase == .idle, FocusDuration.range.contains(seconds) else { return false }
        focusDurationSeconds = seconds
        prepareIdleDuration()
        persist()
        onStatusChange?()
        return true
    }

    private func prepareIdleDuration() {
        guard session.phase == .idle else { return }
        session.duration = Double(focusDurationSeconds)
        session.remaining = session.duration
    }

    func stop() {
        session.stop()
        prepareIdleDuration()
        now = Date()
        expanded = true
        persist()
        onGeometryChange?()
        onStatusChange?()
    }

    func toggleExpanded() {
        if expanded {
            expanded = false
            onGeometryChange?()
        } else { show() }
    }

    func show(focus: Bool = true) {
        isVisible = true
        expanded = true
        onGeometryChange?()
        if focus { onKeyboardFocusRequest?() }
    }

    func hide() {
        isVisible = false
        onGeometryChange?()
    }

    func finish() {
        session.stop()
        prepareIdleDuration()
        now = Date()
        expanded = false
        isVisible = false
        persist()
        onGeometryChange?()
        onStatusChange?()
    }

    func persist() {
        do {
            try JSONEncoder().encode(session).write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
            try JSONEncoder().encode(TimerPreferences(focusDurationSeconds: focusDurationSeconds, focusMinutes: nil))
                .write(to: preferencesURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: preferencesURL.path)
            storageWarning = nil
        } catch {
            storageWarning = "Session recovery unavailable"
            fputs("Pomodoro session could not be saved: \(error.localizedDescription)\n", stderr)
        }
    }

    func snapshot() -> [String: Any] {
        var value: [String: Any] = [
            "phase": session.phase.rawValue, "kind": session.kind.rawValue,
            "task": session.task, "remainingSeconds": Int(ceil(secondsLeft)),
            "durationSeconds": Int(session.duration), "display": clock,
            "focusMinutes": focusMinutes,
            "focusDurationSeconds": focusDurationSeconds,
            "progress": progress,
            "expanded": expanded, "visible": isVisible, "sessionID": session.id.uuidString
        ]
        if let deadline = session.deadline {
            value["endsAt"] = ISO8601DateFormatter().string(from: deadline)
        }
        if let storageWarning { value["warning"] = storageWarning }
        return value
    }

    func handle(_ request: [String: Any]) -> [String: Any] {
        tick()
        guard let action = request["action"] as? String else {
            return ["ok": false, "error": "Missing action"]
        }
        func failure(_ message: String) -> [String: Any] { ["ok": false, "error": message] }
        switch action {
        case "setDuration":
            let usesSeconds = request["durationSeconds"] != nil
            guard let number = (request["durationSeconds"] ?? request["minutes"]) as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                  (1...(usesSeconds ? 10_800 : 180)).contains(number.intValue),
                  number.doubleValue >= 1, number.doubleValue <= (usesSeconds ? 10_800 : 180) else {
                return failure("Focus duration must be from 1 second to 180 minutes")
            }
            guard updateFocusDuration(seconds: number.intValue * (usesSeconds ? 1 : 60)) else {
                return failure("Set the duration before starting a focus session")
            }
        case "setTask":
            guard let text = request["task"] as? String, text.count <= 160,
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                return failure("Task must be plain text of at most 160 characters")
            }
            updateTask(text)
        case "presentation": return ["ok": true, "window": onPresentationStatus?() ?? [:]]
        case "status": break
        case "show": show(focus: request["focus"] as? Bool ?? true)
        case "start", "break":
            if isActive && request["replace"] as? Bool != true {
                return failure("A session is already active. Pause or stop it, or explicitly replace it.")
            }
            let task: String
            if let raw = request["task"] {
                guard let text = raw as? String, text.count <= 160,
                      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    return failure("Task must be plain text of at most 160 characters")
                }
                task = text
            } else { task = action == "break" ? session.task : "" }
            var seconds = action == "break" ? 300.0 : Double(focusDurationSeconds)
            if let raw = request["durationSeconds"] {
                guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, (1...10_800).contains(number.doubleValue),
                      number.doubleValue.rounded() == number.doubleValue else {
                    return failure("Duration must be a whole number from 1 to 10800 seconds")
                }
                seconds = number.doubleValue
            }
            start(task: task, seconds: seconds, kind: action == "break" ? .rest : .focus)
        case "pause":
            if session.phase == .running { pauseOrResume() }
        case "resume":
            if session.phase == .paused { pauseOrResume() }
        case "stop": stop()
        case "hide": hide()
        case "finish": finish()
        case "quit":
            persist()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.onQuit?() }
        default: return failure("Unknown action")
        }
        return ["ok": true, "session": snapshot()]
    }
}
