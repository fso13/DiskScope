import Foundation

/// Formatting helpers for byte sizes and percentages.
public enum ByteFormat {
    private static let units = ["Б", "КБ", "МБ", "ГБ", "ТБ", "ПБ"]

    /// Human readable size using decimal units, matching Finder's "on disk" numbers.
    public static func string(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 Б" }
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let decimals: Int
        if unit == 0 {
            decimals = 0
        } else if value >= 100 {
            decimals = 0
        } else if value >= 10 {
            decimals = 1
        } else {
            decimals = 2
        }
        return "\(number(value, decimals)) \(units[unit])"
    }

    /// Space saving variant for dense labels ("51,8 ГБ" -> "51,8 ГБ").
    public static func compact(_ bytes: Int64) -> String {
        string(bytes)
    }

    public static func percent(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let fraction = Double(part) / Double(total)
        if fraction >= 0.9995 { return "100%" }
        let value = fraction * 100
        let decimals: Int
        if value >= 10, value < 99 {
            decimals = 0
        } else if value >= 1 {
            decimals = 1
        } else {
            decimals = 2
        }
        return "\(number(value, decimals))%"
    }

    public static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "\(Int((seconds * 1000).rounded())) мс" }
        if seconds < 60 { return "\(seconds.formatted(.number.precision(.fractionLength(1)))) с" }
        let minutes = Int(seconds) / 60
        let rest = Int(seconds) % 60
        return "\(minutes) мин \(rest) с"
    }

    private static func number(_ value: Double, _ decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...max(decimals, 0))))
    }
}
