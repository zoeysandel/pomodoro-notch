import Foundation

public enum FocusDuration {
    public static let range = 1...Int(Int32.max)
    public static let maximumMinutes = range.upperBound / 60

    /// A plain number means minutes; mm:ss also allows sessions under a minute.
    public static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let minutes = Int(parts[0]), (0...maximumMinutes).contains(minutes) else { return nil }
        let seconds: Int
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0...59).contains(value) else { return nil }
            seconds = value
        } else { seconds = 0 }
        let duration = minutes * 60 + seconds
        return range.contains(duration) ? duration : nil
    }

    public static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
