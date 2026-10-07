import Foundation

public enum Phase: String, Codable { case idle, running, paused, completed }
public enum SessionKind: String, Codable { case focus, rest }

public struct Session: Codable, Equatable {
    public var phase: Phase = .idle
    public var kind: SessionKind = .focus
    public var task = ""
    public var duration: Double = 1_500
    public var remaining: Double = 1_500
    public var deadline: Date?
    public var id = UUID()

    public init() {}

    public func secondsLeft(at now: Date) -> Double {
        if phase == .running, let deadline { return max(0, deadline.timeIntervalSince(now)) }
        return max(0, remaining)
    }

    public mutating func start(task: String, kind: SessionKind, duration: Double, at now: Date) {
        self = Session()
        self.task = String(task.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        self.kind = kind
        self.duration = duration
        remaining = duration
        deadline = now.addingTimeInterval(duration)
        phase = .running
    }

    @discardableResult public mutating func advance(to now: Date) -> Bool {
        guard phase == .running, secondsLeft(at: now) <= 0 else { return false }
        phase = .completed
        remaining = 0
        deadline = nil
        return true
    }

    @discardableResult public mutating func pause(at now: Date) -> Bool {
        if advance(to: now) { return true }
        guard phase == .running else { return false }
        remaining = secondsLeft(at: now)
        deadline = nil
        phase = .paused
        return false
    }

    public mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(remaining)
        phase = .running
    }

    public mutating func stop() { self = Session() }
}
