import Foundation
import XCTest
@testable import DiskScopeKit

final class LocalizationTests: XCTestCase {
    func testEnglishStringsExist() {
        XCTAssertEqual(L10n.english("Карта"), "Map")
        XCTAssertEqual(L10n.english("Дубликаты"), "Duplicates")
        XCTAssertEqual(L10n.english("Похожие изображения"), "Similar images")
        XCTAssertEqual(L10n.english("В Корзину…"), "To Trash…")
        XCTAssertEqual(AppLanguage.en.locale.identifier, "en_US")
        XCTAssertEqual(AppLanguage.ru.locale.identifier, "ru_RU")
    }

    func testEnglishModelStrings() {
        UserDefaults.standard.set("en", forKey: "app.settings.language")
        defer { UserDefaults.standard.removeObject(forKey: "app.settings.language") }
        XCTAssertEqual(ByteFormat.string(0), "0 B")
        XCTAssertEqual(Plural.files(2), "2 files")
        XCTAssertEqual(Plural.apps(1), "1 app")
        XCTAssertEqual(L10n.t("Карта"), "Map")
    }
}
