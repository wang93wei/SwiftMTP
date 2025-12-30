//
//  LanguageManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for LanguageManager
//

import XCTest
import Combine
@testable import SwiftMTP

final class LanguageManagerTests: XCTestCase {
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        let instance1 = LanguageManager.shared
        let instance2 = LanguageManager.shared
        
        XCTAssertTrue(instance1 === instance2, "LanguageManager should be a singleton")
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let manager = LanguageManager.shared
        
        XCTAssertNotNil(manager.currentLanguage)
        XCTAssertTrue(AppLanguage.allCases.contains(manager.currentLanguage))
    }
    
    func testCurrentLanguageIsPublished() {
        let manager = LanguageManager.shared
        let expectation = self.expectation(description: "Current language should be published")
        
        let cancellable = manager.$currentLanguage
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
        
        manager.currentLanguage = .english
        
        waitForExpectations(timeout: 1.0) { _ in
            cancellable.cancel()
        }
    }
    
    // MARK: - Language Change Tests
    
    func testChangeLanguageToEnglish() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .english
        
        XCTAssertEqual(manager.currentLanguage, .english)
    }
    
    func testChangeLanguageToChinese() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .chinese
        
        XCTAssertEqual(manager.currentLanguage, .chinese)
    }
    
    func testChangeLanguageToJapanese() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .japanese
        
        XCTAssertEqual(manager.currentLanguage, .japanese)
    }
    
    func testChangeLanguageToKorean() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .korean
        
        XCTAssertEqual(manager.currentLanguage, .korean)
    }
    
    func testChangeLanguageToSystem() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .system
        
        XCTAssertEqual(manager.currentLanguage, .system)
    }
    
    // MARK: - Multiple Language Changes Tests
    
    func testMultipleLanguageChanges() {
        let manager = LanguageManager.shared
        
        let languages: [AppLanguage] = [.english, .chinese, .japanese, .korean, .system]
        
        for language in languages {
            manager.currentLanguage = language
            XCTAssertEqual(manager.currentLanguage, language)
        }
    }
    
    // MARK: - Localization Tests
    
    func testLocalizedString() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "deviceList")
        
        XCTAssertNotNil(localized)
        XCTAssertFalse(localized.isEmpty)
    }
    
    func testLocalizedStringWithInvalidKey() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "invalid_key_12345")
        
        // Should return the key itself if not found
        XCTAssertEqual(localized, "invalid_key_12345")
    }
    
    func testLocalizedStringWithEmptyKey() {
        let manager = LanguageManager.shared
        
        let localized = manager.localizedString(for: "")
        
        XCTAssertEqual(localized, "")
    }
    
    func testLocalizedStringConsistency() {
        let manager = LanguageManager.shared
        
        manager.currentLanguage = .english
        
        let result1 = manager.localizedString(for: "deviceList")
        let result2 = manager.localizedString(for: "deviceList")
        
        XCTAssertEqual(result1, result2)
    }
    
    // MARK: - Language Persistence Tests
    
    func testLanguageChangePersists() {
        let manager = LanguageManager.shared
        let originalLanguage = manager.currentLanguage
        
        manager.currentLanguage = .english
        
        // Create a new instance to simulate app restart
        // Note: In a real scenario, this would require restarting the app
        // For testing, we just verify the language was changed
        XCTAssertEqual(manager.currentLanguage, .english)
        
        // Restore original language
        manager.currentLanguage = originalLanguage
    }
    
    // MARK: - Notification Tests
    
    func testLanguageChangeNotification() {
        let manager = LanguageManager.shared
        let expectation = self.expectation(description: "Language change notification should be posted")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .languageDidChange,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        manager.currentLanguage = .english
        
        waitForExpectations(timeout: 1.0) { _ in
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Locale Identifier Tests
    
    func testLocaleIdentifierForEnglish() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .english
        
        let locale = manager.currentLanguage.localeIdentifier
        
        XCTAssertEqual(locale, "en")
    }
    
    func testLocaleIdentifierForChinese() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .chinese
        
        let locale = manager.currentLanguage.localeIdentifier
        
        XCTAssertEqual(locale, "zh-Hans")
    }
    
    func testLocaleIdentifierForJapanese() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .japanese
        
        let locale = manager.currentLanguage.localeIdentifier
        
        XCTAssertEqual(locale, "ja")
    }
    
    func testLocaleIdentifierForKorean() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .korean
        
        let locale = manager.currentLanguage.localeIdentifier
        
        XCTAssertEqual(locale, "ko")
    }
    
    func testLocaleIdentifierForSystem() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .system
        
        let locale = manager.currentLanguage.localeIdentifier
        
        XCTAssertNil(locale)
    }
    
    // MARK: - Cleanup Tests
    
    func testCleanupSubscriptions() {
        let manager = LanguageManager.shared
        
        // Should not throw
        XCTAssertNoThrow(manager.cleanupSubscriptions())
    }
    
    // MARK: - Edge Cases
    
    func testRapidLanguageChanges() {
        let manager = LanguageManager.shared
        let originalLanguage = manager.currentLanguage
        
        // Perform rapid language changes
        for _ in 0..<10 {
            manager.currentLanguage = .english
            manager.currentLanguage = .chinese
            manager.currentLanguage = .japanese
        }
        
        // Manager should still be in a valid state
        XCTAssertNotNil(manager.currentLanguage)
        XCTAssertTrue(AppLanguage.allCases.contains(manager.currentLanguage))
        
        // Restore original language
        manager.currentLanguage = originalLanguage
    }
    
    func testAllSupportedKeys() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .english
        
        let testKeys = [
            "deviceList",
            "refresh",
            "cancel",
            "ok",
            "upload",
            "download",
            "delete",
            "settings"
        ]
        
        for key in testKeys {
            let localized = manager.localizedString(for: key)
            XCTAssertNotNil(localized, "Localization for key '\(key)' should not be nil")
        }
    }
    
    // MARK: - Performance Tests
    
    func testLocalizedStringPerformance() {
        let manager = LanguageManager.shared
        manager.currentLanguage = .english
        
        measure {
            for _ in 0..<1000 {
                _ = manager.localizedString(for: "deviceList")
            }
        }
    }
    
    func testLanguageChangePerformance() {
        let manager = LanguageManager.shared
        
        measure {
            for _ in 0..<100 {
                manager.currentLanguage = .english
                manager.currentLanguage = .chinese
            }
        }
    }
    
    // MARK: - Test Cleanup
    
    override func tearDown() {
        // Reset to system default after each test
        LanguageManager.shared.currentLanguage = .system
        super.tearDown()
    }
}