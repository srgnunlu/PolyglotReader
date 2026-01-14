import XCTest
@testable import PolyglotReader

/// Base class for UI tests providing common setup and utilities
class UITestBase: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        
        // Stop immediately when a failure occurs
        continueAfterFailure = false
        
        // Initialize app
        app = XCUIApplication()
        
        // Set launch arguments for testing
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_MODE": "true",
            "ANIMATIONS_DISABLED": "true"
        ]
        
        // Launch the app
        app.launch()
    }
    
    override func tearDown() {
        app = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Wait for an element to exist with timeout
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        element.waitForExistence(timeout: timeout)
    }
    
    /// Wait for an element to become hittable
    func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// Tap an element if it exists
    func tapIfExists(_ element: XCUIElement) {
        if element.exists && element.isHittable {
            element.tap()
        }
    }
    
    /// Take a screenshot (useful for debugging)
    func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    /// Dismiss any system alerts (e.g., permission dialogs)
    func dismissSystemAlerts() {
        // Handle common system alerts
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
        
        let okButton = springboard.buttons["OK"]
        if okButton.waitForExistence(timeout: 1) {
            okButton.tap()
        }
    }
    
    /// Check if the app is on the login screen
    var isOnLoginScreen: Bool {
        // Look for common login screen elements using accessibility identifiers
        return app.buttons["google_sign_in_button"].exists ||
               app.buttons["apple_sign_in_button"].exists ||
               app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google'")).firstMatch.exists ||
               app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Apple'")).firstMatch.exists ||
               app.staticTexts["Polyglot Reader"].exists
    }
    
    /// Check if the app is on the main library screen
    var isOnLibraryScreen: Bool {
        return app.navigationBars["Kütüphane"].exists ||
               app.navigationBars["Library"].exists
    }
}

// MARK: - Accessibility Identifiers

/// Constants for accessibility identifiers used in UI tests
enum AccessibilityID {
    // Auth
    static let googleSignInButton = "google_sign_in_button"
    static let appleSignInButton = "apple_sign_in_button"
    
    // Library
    static let libraryView = "library_view"
    static let addPDFButton = "add_pdf_button"
    static let pdfGridItem = "pdf_grid_item"
    
    // Reader
    static let pdfReaderView = "pdf_reader_view"
    static let pageNavigator = "page_navigator"
    static let chatButton = "chat_button"
    
    // Chat
    static let chatView = "chat_view"
    static let messageInput = "message_input"
    static let sendButton = "send_button"
    
    // Settings
    static let settingsButton = "settings_button"
    static let settingsView = "settings_view"
    static let themeToggle = "theme_toggle"
    static let logoutButton = "logout_button"
}
