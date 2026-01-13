//
//  LanguageManagerTests.swift
//  SwiftMTPTests
//
//  Unit tests for LanguageManager
//

import XCTest
import Combine
@testable import SwiftMTP

@MainActor
final class LanguageManagerTests: XCTestCase {
    
    var manager: LanguageManager!
    var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        manager = LanguageManager.shared
        cancellables = Set<AnyCancellable>()
        
        // Reset to system default before each test
        manager.currentLanguage = .system
    }
    
    override func tearDown() {
        // Reset to system default after each test
        manager.currentLanguage = .system
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        let instance1 = LanguageManager.shared
        let instance2 = LanguageManager.shared
        
        XCTAssertTrue(instance1 === instance2, "LanguageManager should be a singleton")
    }
    
    // MARK: - Published Properties Tests
    
    func testCurrentLanguageIsPublished() {
        let expectation = self.expectation(description: "currentLanguage property should be published")
        
        manager.$currentLanguage
            .dropFirst() // Skip initial value
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        manager.currentLanguage = .english
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Language Switching Tests
    
    func testSwitchToEnglish() {
        manager.currentLanguage = .english
        
        XCTAssertEqual(manager.currentLanguage, .english)
    }
    
    func testSwitchToChinese() {
        manager.currentLanguage = .chinese
        
        XCTAssertEqual(manager.currentLanguage, .chinese)
    }
    
    func testSwitchToJapanese() {
        manager.currentLanguage = .japanese
        
        XCTAssertEqual(manager.currentLanguage, .japanese)
    }
    
    func testSwitchToKorean() {
        manager.currentLanguage = .korean
        
        XCTAssertEqual(manager.currentLanguage, .korean)
    }
    
    func testSwitchToRussian() {
        manager.currentLanguage = .russian
        
        XCTAssertEqual(manager.currentLanguage, .russian)
    }
    
    func testSwitchToFrench() {
        manager.currentLanguage = .french
        
        XCTAssertEqual(manager.currentLanguage, .french)
    }
    
    func testSwitchToGerman() {
        manager.currentLanguage = .german
        
        XCTAssertEqual(manager.currentLanguage, .german)
    }
    
    func testSwitchToSystem() {
        manager.currentLanguage = .english
        
        manager.currentLanguage = .system
        
        XCTAssertEqual(manager.currentLanguage, .system)
    }
    
    func testMultipleLanguageSwitches() {
        manager.currentLanguage = .english
        XCTAssertEqual(manager.currentLanguage, .english)
        
        manager.currentLanguage = .chinese
        XCTAssertEqual(manager.currentLanguage, .chinese)
        
        manager.currentLanguage = .japanese
        XCTAssertEqual(manager.currentLanguage, .japanese)
        
        manager.currentLanguage = .system
        XCTAssertEqual(manager.currentLanguage, .system)
    }
    
    // MARK: - Localization Tests
    
    func testLocalizedStringWithValidKey() {
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "deviceList")
        
        XCTAssertNotNil(localized)
        XCTAssertNotEqual(localized, "deviceList")
    }
    
    func testLocalizedStringWithInvalidKey() {
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "invalid_key_12345")
        
        // Should return the key itself if not found
        XCTAssertEqual(localized, "invalid_key_12345")
    }
    
    func testLocalizedStringWithEmptyKey() {
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "")
        
        XCTAssertEqual(localized, "")
    }
    
    func testLocalizedStringInDifferentLanguages() {
        let testKey = "deviceList"
        
        manager.currentLanguage = .english
        let english = manager.localizedString(for: testKey)
        
        manager.currentLanguage = .chinese
        let chinese = manager.localizedString(for: testKey)
        
        // Different languages should return different strings (if translations exist)
        // Or at least should not crash
        XCTAssertNotNil(english)
        XCTAssertNotNil(chinese)
    }
    
    func testLocalizedStringFallback() {
        // Test that fallback to main bundle works
        manager.currentLanguage = .chinese
        
        let localized = manager.localizedString(for: "deviceList")
        
        // Should return something (either Chinese or English fallback)
        XCTAssertNotNil(localized)
    }
    
    // MARK: - Persistence Tests
    
    func testLanguagePersistence() {
        manager.currentLanguage = .japanese
        
        // Create a new instance to test persistence
        // Note: This won't work perfectly because LanguageManager is a singleton
        // but we can verify that the value is saved to UserDefaults
        
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        XCTAssertEqual(savedLanguage, "ja")
    }
    
    func testLanguagePersistenceReset() {
        manager.currentLanguage = .chinese
        manager.currentLanguage = .system
        
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        XCTAssertEqual(savedLanguage, "system")
    }
    
    // MARK: - Notification Tests
    
    func testLanguageChangedNotification() {
        let expectation = self.expectation(description: "languageDidChange notification should be sent")
        
        NotificationCenter.default.publisher(for: .languageDidChange)
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        manager.currentLanguage = .english
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testLanguageChangedNotificationMultipleTimes() {
        let expectation = self.expectation(description: "Multiple languageDidChange notifications should be sent")
        expectation.expectedFulfillmentCount = 3
        
        NotificationCenter.default.publisher(for: .languageDidChange)
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        manager.currentLanguage = .english
        manager.currentLanguage = .chinese
        manager.currentLanguage = .japanese
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Bundle Tests
    
    func testBundleUpdateOnLanguageChange() {
        manager.currentLanguage = .english
        
        let englishBundle = manager.localizedString(for: "deviceList")
        
        manager.currentLanguage = .chinese
        
        let chineseBundle = manager.localizedString(for: "deviceList")
        
        // Bundle should be updated
        // The actual values depend on available translations
        XCTAssertNotNil(englishBundle)
        XCTAssertNotNil(chineseBundle)
    }
    
    func testBundleFallbackToMain() {
        // Test that bundle falls back to main bundle if language bundle is not found
        // This is tested implicitly through localizedString tests
        manager.currentLanguage = .system
        
        let localized = manager.localizedString(for: "deviceList")
        
        XCTAssertNotNil(localized)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentLanguageSwitches() {
        let expectation = self.expectation(description: "Concurrent language switches should complete")
        expectation.expectedFulfillmentCount = 10
        
        DispatchQueue.concurrentPerform(iterations: 10) { i in
            let languages: [AppLanguage] = [.english, .chinese, .japanese, .korean, .system]
            manager.currentLanguage = languages[i % languages.count]
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        // Should complete without crashing
        XCTAssertNotNil(manager.currentLanguage)
    }
    
    func testConcurrentLocalizedStringAccess() {
        let expectation = self.expectation(description: "Concurrent localizedString access should complete")
        expectation.expectedFulfillmentCount = 10
        
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let localized = manager.localizedString(for: "deviceList")
            XCTAssertNotNil(localized)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Edge Cases
    
    func testLanguageSwitchWithNilKey() {
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "")
        
        XCTAssertEqual(localized, "")
    }
    
    func testLanguageSwitchWithSpecialCharacters() {
        manager.currentLanguage = .english
        
        let localized = manager.localizedString(for: "key_with_special_chars_!@#$%^&*()")
        
        // Should return the key itself if not found
        XCTAssertEqual(localized, "key_with_special_chars_!@#$%^&*()")
    }
    
    func testLanguageSwitchWithVeryLongKey() {
        manager.currentLanguage = .english
        
        let longKey = String(repeating: "a", count: 1000)
        let localized = manager.localizedString(for: longKey)
        
        // Should return the key itself if not found
        XCTAssertEqual(localized, longKey)
    }
    
    func testLanguageSwitchWithUnicodeKey() {
        manager.currentLanguage = .chinese
        
        let localized = manager.localizedString(for: "测试键")
        
        // Should return the key itself if not found
        XCTAssertEqual(localized, "测试键")
    }
    
    // MARK: - Performance Tests
    
    func testLanguageSwitchPerformance() {
        measure {
            for _ in 0..<100 {
                manager.currentLanguage = .english
                manager.currentLanguage = .chinese
                manager.currentLanguage = .japanese
            }
        }
    }
    
    func testLocalizedStringPerformance() {
        manager.currentLanguage = .english
        
        measure {
            for _ in 0..<1000 {
                _ = manager.localizedString(for: "deviceList")
            }
        }
    }
    
    // MARK: - Cleanup Tests
    
    func testCleanupSubscriptions() {
        // Add a subscription
        manager.$currentLanguage
            .sink { _ in }
            .store(in: &cancellables)
        
        // Cleanup should not throw
        XCTAssertNoThrow(manager.cleanupSubscriptions())
    }
}