//
//  AppLanguageTests.swift
//  SwiftMTPTests
//
//  Unit tests for AppLanguage enum
//

import XCTest
@testable import SwiftMTP

final class AppLanguageTests: XCTestCase {
    
    // MARK: - Raw Value Tests
    
    func testRawValues() {
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.chinese.rawValue, "zh")
        XCTAssertEqual(AppLanguage.japanese.rawValue, "ja")
        XCTAssertEqual(AppLanguage.korean.rawValue, "ko")
    }
    
    func testAllCases() {
        let languages: [AppLanguage] = [
            .system,
            .english,
            .chinese,
            .japanese,
            .korean
        ]
        XCTAssertEqual(languages.count, 5)
    }
    
    // MARK: - ID Tests
    
    func testIdProperty() {
        XCTAssertEqual(AppLanguage.system.id, "system")
        XCTAssertEqual(AppLanguage.english.id, "en")
        XCTAssertEqual(AppLanguage.chinese.id, "zh")
        XCTAssertEqual(AppLanguage.japanese.id, "ja")
        XCTAssertEqual(AppLanguage.korean.id, "ko")
    }
    
    // MARK: - Display Name Tests
    
    func testDisplayNameRaw() {
        XCTAssertEqual(AppLanguage.system.displayNameRaw, "System Default")
        XCTAssertEqual(AppLanguage.english.displayNameRaw, "English")
        XCTAssertEqual(AppLanguage.chinese.displayNameRaw, "中文")
        XCTAssertEqual(AppLanguage.japanese.displayNameRaw, "日本語")
        XCTAssertEqual(AppLanguage.korean.displayNameRaw, "한국어")
    }
    
    func testDisplayNameRawContainsExpectedCharacters() {
        // Test that display names contain expected characters
        XCTAssertTrue(AppLanguage.english.displayNameRaw.contains("English"))
        XCTAssertTrue(AppLanguage.chinese.displayNameRaw.contains("中文"))
        XCTAssertTrue(AppLanguage.japanese.displayNameRaw.contains("日本"))
        XCTAssertTrue(AppLanguage.korean.displayNameRaw.contains("한국"))
    }
    
    // MARK: - Locale Identifier Tests
    
    func testLocaleIdentifier() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
        XCTAssertEqual(AppLanguage.chinese.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.japanese.localeIdentifier, "ja")
        XCTAssertEqual(AppLanguage.korean.localeIdentifier, "ko")
    }
    
    // MARK: - CaseIterable Tests
    
    func testCaseIterable() {
        let allLanguages = AppLanguage.allCases
        XCTAssertEqual(allLanguages.count, 5)
        
        XCTAssertTrue(allLanguages.contains(.system))
        XCTAssertTrue(allLanguages.contains(.english))
        XCTAssertTrue(allLanguages.contains(.chinese))
        XCTAssertTrue(allLanguages.contains(.japanese))
        XCTAssertTrue(allLanguages.contains(.korean))
    }
    
    // MARK: - Identifiable Tests
    
    func testIdentifiable() {
        let languages: [AppLanguage] = [.system, .english, .chinese, .japanese, .korean]
        
        let ids = languages.map { $0.id }
        let uniqueIds = Set(ids)
        
        XCTAssertEqual(ids.count, uniqueIds.count, "All language IDs should be unique")
    }
    
    // MARK: - Initialization from Raw Value
    
    func testInitFromRawValue() {
        XCTAssertEqual(AppLanguage(rawValue: "system"), .system)
        XCTAssertEqual(AppLanguage(rawValue: "en"), .english)
        XCTAssertEqual(AppLanguage(rawValue: "zh"), .chinese)
        XCTAssertEqual(AppLanguage(rawValue: "ja"), .japanese)
        XCTAssertEqual(AppLanguage(rawValue: "ko"), .korean)
    }
    
    func testInitFromInvalidRawValue() {
        XCTAssertNil(AppLanguage(rawValue: "invalid"))
        XCTAssertNil(AppLanguage(rawValue: ""))
        XCTAssertNil(AppLanguage(rawValue: "EN")) // Case sensitive
    }
    
    // MARK: - String Comparison Tests
    
    func testRawValueEquality() {
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.english.id, "en")
    }
    
    func testCaseSensitivity() {
        XCTAssertNotEqual(AppLanguage(rawValue: "EN"), .english)
        XCTAssertNotEqual(AppLanguage(rawValue: "ZH"), .chinese)
        XCTAssertNotEqual(AppLanguage(rawValue: "JA"), .japanese)
        XCTAssertNotEqual(AppLanguage(rawValue: "KO"), .korean)
    }
    
    // MARK: - Display Name Uniqueness Tests
    
    func testDisplayNamesAreUnique() {
        let languages: [AppLanguage] = [.system, .english, .chinese, .japanese, .korean]
        let displayNames = languages.map { $0.displayNameRaw }
        let uniqueNames = Set(displayNames)
        
        XCTAssertEqual(displayNames.count, uniqueNames.count, "All display names should be unique")
    }
    
    // MARK: - Locale Identifier Uniqueness Tests
    
    func testLocaleIdentifiersAreUnique() {
        let languages: [AppLanguage] = [.system, .english, .chinese, .japanese, .korean]
        let localeIdentifiers = languages.compactMap { $0.localeIdentifier }
        let uniqueLocales = Set(localeIdentifiers)
        
        XCTAssertEqual(localeIdentifiers.count, uniqueLocales.count, "All locale identifiers should be unique")
    }
    
    // MARK: - System Language Special Case
    
    func testSystemLanguageHasNilLocale() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.system.displayNameRaw, "System Default")
    }
    
    func testSystemLanguageRawValue() {
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
    }
    
    // MARK: - Chinese Language Variants
    
    func testChineseLanguageIsSimplified() {
        XCTAssertEqual(AppLanguage.chinese.localeIdentifier, "zh-Hans")
        XCTAssertTrue(AppLanguage.chinese.displayNameRaw.contains("中文"))
    }
    
    // MARK: - Language Ordering in AllCases
    
    func testAllCasesOrder() {
        let allCases = AppLanguage.allCases
        XCTAssertEqual(allCases[0], .system)
        XCTAssertEqual(allCases[1], .english)
        XCTAssertEqual(allCases[2], .chinese)
        XCTAssertEqual(allCases[3], .japanese)
        XCTAssertEqual(allCases[4], .korean)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStringRawValue() {
        XCTAssertNil(AppLanguage(rawValue: ""))
    }
    
    func testWhitespaceRawValue() {
        XCTAssertNil(AppLanguage(rawValue: " "))
        XCTAssertNil(AppLanguage(rawValue: "\t"))
        XCTAssertNil(AppLanguage(rawValue: "\n"))
    }
    
    func testPartialRawValue() {
        XCTAssertNil(AppLanguage(rawValue: "e"))
        XCTAssertNil(AppLanguage(rawValue: "z"))
        XCTAssertNil(AppLanguage(rawValue: "j"))
        XCTAssertNil(AppLanguage(rawValue: "k"))
    }
    
    // MARK: - Unicode Tests
    
    func testUnicodeInDisplayNames() {
        // Test that Chinese, Japanese, and Korean display names contain valid Unicode
        let chineseName = AppLanguage.chinese.displayNameRaw
        let japaneseName = AppLanguage.japanese.displayNameRaw
        let koreanName = AppLanguage.korean.displayNameRaw
        
        // These should not be empty
        XCTAssertFalse(chineseName.isEmpty)
        XCTAssertFalse(japaneseName.isEmpty)
        XCTAssertFalse(koreanName.isEmpty)
        
        // These should contain non-ASCII characters
        let chineseData = chineseName.data(using: .utf8)!
        let japaneseData = japaneseName.data(using: .utf8)!
        let koreanData = koreanName.data(using: .utf8)!
        
        XCTAssertGreaterThan(chineseData.count, chineseName.count)
        XCTAssertGreaterThan(japaneseData.count, japaneseName.count)
        XCTAssertGreaterThan(koreanData.count, koreanName.count)
    }
    
    // MARK: - Consistency Tests
    
    func testRawValueIdConsistency() {
        let languages: [AppLanguage] = [.system, .english, .chinese, .japanese, .korean]
        
        for language in languages {
            XCTAssertEqual(language.rawValue, language.id, "rawValue and id should be consistent for \(language)")
        }
    }
    
    // MARK: - Hashable Tests
    
    func testHashable() {
        let set: Set<AppLanguage> = [.system, .english, .chinese, .japanese, .korean]
        XCTAssertEqual(set.count, 5)
    }
    
    func testHashableInsertDuplicate() {
        var set: Set<AppLanguage> = []
        set.insert(.english)
        set.insert(.english)
        
        XCTAssertEqual(set.count, 1)
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        XCTAssertEqual(AppLanguage.english, AppLanguage.english)
        XCTAssertNotEqual(AppLanguage.english, AppLanguage.chinese)
        XCTAssertNotEqual(AppLanguage.chinese, AppLanguage.japanese)
        XCTAssertNotEqual(AppLanguage.japanese, AppLanguage.korean)
    }
    
    // MARK: - Performance Tests
    
    func testAllCasesPerformance() {
        measure {
            _ = AppLanguage.allCases
        }
    }
    
    func testRawValueLookupPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = AppLanguage(rawValue: "en")
                _ = AppLanguage(rawValue: "zh")
                _ = AppLanguage(rawValue: "ja")
            }
        }
    }
}