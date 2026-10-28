public enum DurationFormat {
    /// `754.9` → `"00:12:34"`. Hours keep growing past 99.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return [hours, minutes, secs].map { $0 < 10 ? "0\($0)" : "\($0)" }.joined(separator: ":")
    }
}
