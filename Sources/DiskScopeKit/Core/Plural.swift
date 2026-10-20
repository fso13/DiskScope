import Foundation

public enum Plural {
    public static func files(_ count: Int) -> String {
        "\(ByteFormat.count(count)) \(word(count, "файл", "файла", "файлов"))"
    }

    public static func folders(_ count: Int) -> String {
        "\(ByteFormat.count(count)) \(word(count, "папка", "папки", "папок"))"
    }

    public static func items(_ count: Int) -> String {
        "\(ByteFormat.count(count)) \(word(count, "объект", "объекта", "объектов"))"
    }

    public static func apps(_ count: Int) -> String {
        "\(ByteFormat.count(count)) \(word(count, "приложение", "приложения", "приложений"))"
    }

    public static func elements(_ count: Int) -> String {
        "\(ByteFormat.count(count)) \(word(count, "элемент", "элемента", "элементов"))"
    }

    public static func smallFiles(_ count: Int) -> String {
        "\(ByteFormat.count(count)) \(word(count, "мелкий файл", "мелких файла", "мелких файлов"))"
    }

    public static func word(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let absolute = abs(count)
        let lastTwo = absolute % 100
        if (11...14).contains(lastTwo) { return many }
        switch absolute % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
