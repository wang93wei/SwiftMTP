//
//  AppLanguageTests.swift
//  SwiftMTPTests
//
//  Unit tests for AppLanguage enum
//

import XCTest
@testable import SwiftMTP

final class AppLanguageTests: XCTestCase {
    
    // MARK: - CaseIterable Tests
    
    func testAllCases() {
        let allCases = AppLanguage.allCases
        
        XCTAssertEqual(allCases.count, 8)
        XCTAssertTrue(allCases.contains(.system))
        XCTAssertTrue(allCases.contains(.english))
        XCTAssertTrue(allCases.contains(.chinese))
        XCTAssertTrue(allCases.contains(.japanese))
        XCTAssertTrue(allCases.contains(.korean))
        XCTAssertTrue(allCases.contains(.russian))
        XCTAssertTrue(allCases.contains(.french))
        XCTAssertTrue(allCases.contains(.german))
    }
    
    // MARK: - Identifiable Tests
    
    func testIdProperty() {
        XCTAssertEqual(AppLanguage.system.id, "system")
        XCTAssertEqual(AppLanguage.english.id, "en")
        XCTAssertEqual(AppLanguage.chinese.id, "zh")
        XCTAssertEqual(AppLanguage.japanese.id, "ja")
        XCTAssertEqual(AppLanguage.korean.id, "ko")
        XCTAssertEqual(AppLanguage.russian.id, "ru")
        XCTAssertEqual(AppLanguage.french.id, "fr")
        XCTAssertEqual(AppLanguage.german.id, "de")
    }
    
    func testIdMatchesRawValue() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(language.id, language.rawValue)
        }
    }
    
    // MARK: - RawValue Tests
    
    func testRawValues() {
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.chinese.rawValue, "zh")
        XCTAssertEqual(AppLanguage.japanese.rawValue, "ja")
        XCTAssertEqual(AppLanguage.korean.rawValue, "ko")
        XCTAssertEqual(AppLanguage.russian.rawValue, "ru")
        XCTAssertEqual(AppLanguage.french.rawValue, "fr")
        XCTAssertEqual(AppLanguage.german.rawValue, "de")
    }
    
    // MARK: - DisplayName Tests
    
    func testDisplayName() {
        // Note: displayName depends on L10n, which may not be available in tests
        // We just verify that it returns a non-empty string
        for language in AppLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty, "displayName for \(language.rawValue) should not be empty")
        }
    }
    
    func testDisplayNameRaw() {
        XCTAssertEqual(AppLanguage.system.displayNameRaw, "System Default")
        XCTAssertEqual(AppLanguage.english.displayNameRaw, "English")
        XCTAssertEqual(AppLanguage.chinese.displayNameRaw, "中文")
        XCTAssertEqual(AppLanguage.japanese.displayNameRaw, "日本語")
        XCTAssertEqual(AppLanguage.korean.displayNameRaw, "한국어")
        XCTAssertEqual(AppLanguage.russian.displayNameRaw, "Русский")
        XCTAssertEqual(AppLanguage.french.displayNameRaw, "Français")
        XCTAssertEqual(AppLanguage.german.displayNameRaw, "Deutsch")
    }
    
    // MARK: - LocaleIdentifier Tests
    
    func testLocaleIdentifier() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
        XCTAssertEqual(AppLanguage.chinese.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.japanese.localeIdentifier, "ja")
        XCTAssertEqual(AppLanguage.korean.localeIdentifier, "ko")
        XCTAssertEqual(AppLanguage.russian.localeIdentifier, "ru")
        XCTAssertEqual(AppLanguage.french.localeIdentifier, "fr")
        XCTAssertEqual(AppLanguage.german.localeIdentifier, "de")
    }
    
    // MARK: - Initialization Tests
    
    func testInitFromRawValue() {
        let system = AppLanguage(rawValue: "system")
        XCTAssertEqual(system, .system)
        
        let english = AppLanguage(rawValue: "en")
        XCTAssertEqual(english, .english)
        
        let chinese = AppLanguage(rawValue: "zh")
        XCTAssertEqual(chinese, .chinese)
        
        let japanese = AppLanguage(rawValue: "ja")
        XCTAssertEqual(japanese, .japanese)
        
        let korean = AppLanguage(rawValue: "ko")
        XCTAssertEqual(korean, .korean)
        
        let russian = AppLanguage(rawValue: "ru")
        XCTAssertEqual(russian, .russian)
        
        let french = AppLanguage(rawValue: "fr")
        XCTAssertEqual(french, .french)
        
        let german = AppLanguage(rawValue: "de")
        XCTAssertEqual(german, .german)
    }
    
    func testInitFromInvalidRawValue() {
        let invalid = AppLanguage(rawValue: "invalid_language")
        XCTAssertNil(invalid)
    }
    
    func testInitFromEmptyRawValue() {
        let empty = AppLanguage(rawValue: "")
        XCTAssertNil(empty)
    }
    
    func testInitFromNilRawValue() {
        let nilValue = AppLanguage(rawValue: "nil")
        XCTAssertNil(nilValue)
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        XCTAssertEqual(AppLanguage.english, AppLanguage.english)
        XCTAssertNotEqual(AppLanguage.english, AppLanguage.chinese)
        XCTAssertNotEqual(AppLanguage.chinese, AppLanguage.japanese)
    }
    
    func testEqualityWithSameRawValue() {
        let english1 = AppLanguage(rawValue: "en")
        let english2 = AppLanguage(rawValue: "en")
        
        XCTAssertEqual(english1, english2)
    }
    
    // MARK: - Hashable Tests
    
    func testHashable() {
        let languages: Set<AppLanguage> = [.english, .chinese, .japanese]
        
        XCTAssertEqual(languages.count, 3)
        XCTAssertTrue(languages.contains(.english))
        XCTAssertTrue(languages.contains(.chinese))
        XCTAssertTrue(languages.contains(.japanese))
    }
    
    func testHashableWithDuplicates() {
        var languages: Set<AppLanguage> = []
        languages.insert(.english)
        languages.insert(.english)
        languages.insert(.chinese)
        
        XCTAssertEqual(languages.count, 2)
    }
    
    // MARK: - Comparable Tests (if applicable)

    func testSorting() {
        let languages: [AppLanguage] = [.japanese, .english, .chinese, .system]
        let sorted = languages.sorted { $0.rawValue < $1.rawValue }

        XCTAssertEqual(sorted[0].rawValue, "chinese")
        XCTAssertEqual(sorted[1].rawValue, "english")
        XCTAssertEqual(sorted[2].rawValue, "japanese")
        XCTAssertEqual(sorted[3].rawValue, "system")
    }

    // MARK: - Codable Tests

    // Note: AppLanguage does not conform to Codable, so these tests are disabled
    // To enable Codable support, add `: Codable` to the enum declaration

    /*
    func testCodableEncoding() throws {
        let language = AppLanguage.chinese
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(language)

        XCTAssertFalse(encoded.isEmpty)
    }

    func testCodableDecoding() throws {
        let json = """
        {
            "rawValue": "en"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppLanguage.self, from: json)

        XCTAssertEqual(decoded, .english)
    }

    func testCodableRoundTrip() throws {
        let original = AppLanguage.japanese
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AppLanguage.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
    */
    
    // MARK: - Edge Cases
    
    func testDisplayNameWithSpecialCharacters() {
        // displayNameRaw contains Unicode characters
        let chinese = AppLanguage.chinese.displayNameRaw
        XCTAssertTrue(chinese.contains("中文"))
        
        let japanese = AppLanguage.japanese.displayNameRaw
        XCTAssertTrue(japanese.contains("日本語"))
        
        let korean = AppLanguage.korean.displayNameRaw
        XCTAssertTrue(korean.contains("한국어"))
        
        let russian = AppLanguage.russian.displayNameRaw
        XCTAssertTrue(russian.contains("Русский"))
        
        let french = AppLanguage.french.displayNameRaw
        XCTAssertTrue(french.contains("Français"))
        
        let german = AppLanguage.german.displayNameRaw
        XCTAssertTrue(german.contains("Deutsch"))
    }
    
    func testLocaleIdentifierWithVariants() {
        // Test that locale identifiers are correctly formatted
        XCTAssertEqual(AppLanguage.chinese.localeIdentifier, "zh-Hans") // Simplified Chinese
        XCTAssertNotEqual(AppLanguage.chinese.localeIdentifier, "zh-Hant") // Not Traditional Chinese
    }
    
    func testSystemLanguageHasNilLocaleIdentifier() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
    }
    
    // MARK: - Performance Tests
    
    func testDisplayNamePerformance() {
        measure {
            for _ in 0..<1000 {
                _ = AppLanguage.english.displayName
                _ = AppLanguage.chinese.displayName
                _ = AppLanguage.japanese.displayName
            }
        }
    }
    
    func testDisplayNameRawPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = AppLanguage.english.displayNameRaw
                _ = AppLanguage.chinese.displayNameRaw
                _ = AppLanguage.japanese.displayNameRaw
            }
        }
    }
    
    func testLocaleIdentifierPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = AppLanguage.english.localeIdentifier
                _ = AppLanguage.chinese.localeIdentifier
                _ = AppLanguage.japanese.localeIdentifier
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testLanguageManagerIntegration() {
        let manager = LanguageManager.shared
        
        // Test that AppLanguage values work with LanguageManager
        manager.currentLanguage = .english
        XCTAssertEqual(manager.currentLanguage, .english)
        
        manager.currentLanguage = .chinese
        XCTAssertEqual(manager.currentLanguage, .chinese)
        
        manager.currentLanguage = .system
        XCTAssertEqual(manager.currentLanguage, .system)
    }
    
    func testAllLanguagesWithLanguageManager() {
        let manager = LanguageManager.shared
        
        for language in AppLanguage.allCases {
            manager.currentLanguage = language
            XCTAssertEqual(manager.currentLanguage, language)
        }
    }
}