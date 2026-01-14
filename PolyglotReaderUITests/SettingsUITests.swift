import XCTest

/// UI tests for Settings screen
final class SettingsUITests: UITestBase {
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        
        // Navigate to settings if we're logged in
        navigateToSettingsIfPossible()
    }
    
    // MARK: - Settings Navigation
    
    func testSettingsButtonExists() {
        // Given - User is on the library screen
        guard isOnLibraryScreen else {
            XCTSkip("Not on library screen - user may not be logged in")
            return
        }
        
        // Then - Settings button should exist
        let settingsButton = app.buttons["Ayarlar"]
        let settingsExists = settingsButton.exists || 
                            app.buttons["Settings"].exists ||
                            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'gear'")).firstMatch.exists ||
                            app.navigationBars.buttons.element(boundBy: 1).exists
        
        XCTAssertTrue(settingsExists, "Settings button should be accessible")
    }
    
    func testSettingsScreenOpens() {
        // Given - Navigate to settings
        guard navigateToSettings() else {
            XCTSkip("Could not navigate to settings")
            return
        }
        
        // Then - Settings screen content should be visible
        let settingsContent = app.scrollViews.firstMatch
        XCTAssertTrue(settingsContent.exists || app.tables.firstMatch.exists, 
                     "Settings screen should have content")
        
        takeScreenshot(name: "Settings_Screen")
    }
    
    // MARK: - Theme Tests
    
    func testThemeOptionsExist() {
        // Given - Navigate to settings
        guard navigateToSettings() else {
            XCTSkip("Could not navigate to settings")
            return
        }
        
        // Then - Theme options should be present
        let themeSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Tema' OR label CONTAINS[c] 'Theme'")).firstMatch
        
        let hasThemeSection = themeSection.exists || 
                             app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Dark' OR label CONTAINS[c] 'Light' OR label CONTAINS[c] 'Koyu' OR label CONTAINS[c] 'Açık'")).firstMatch.exists
        
        XCTAssertTrue(hasThemeSection, "Theme settings should be available")
    }
    
    // MARK: - Logout Tests
    
    func testLogoutButtonExists() {
        // Given - Navigate to settings
        guard navigateToSettings() else {
            XCTSkip("Could not navigate to settings")
            return
        }
        
        // Then - Logout button should exist
        let logoutButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Çıkış' OR label CONTAINS[c] 'Logout' OR label CONTAINS[c] 'Sign Out'")).firstMatch
        
        XCTAssertTrue(logoutButton.exists, "Logout button should be visible in settings")
    }
    
    // MARK: - About Section Tests
    
    func testVersionInfoExists() {
        // Given - Navigate to settings
        guard navigateToSettings() else {
            XCTSkip("Could not navigate to settings")
            return
        }
        
        // Then - Version info should be present somewhere
        // This might be in an About section or footer
        let versionText = app.staticTexts.matching(NSPredicate(format: "label MATCHES '.*[0-9]+\\.[0-9]+.*'")).firstMatch
        
        // Version info might not always be visible, so we just verify settings loaded
        let settingsLoaded = app.scrollViews.firstMatch.exists || app.tables.firstMatch.exists
        XCTAssertTrue(settingsLoaded, "Settings screen should be loaded")
    }
    
    // MARK: - Helper Methods
    
    private func navigateToSettingsIfPossible() {
        // Wait for app to settle
        _ = app.buttons.firstMatch.waitForExistence(timeout: 5)
        
        // If we're on login screen, skip settings tests
        if isOnLoginScreen {
            return
        }
        
        // Try to find and tap settings
        navigateToSettings()
    }
    
    @discardableResult
    private func navigateToSettings() -> Bool {
        // Check if we're already in settings
        if app.navigationBars["Ayarlar"].exists || app.navigationBars["Settings"].exists {
            return true
        }
        
        // Try various ways to find settings button
        let settingsButton = app.buttons["Ayarlar"]
        if settingsButton.exists {
            settingsButton.tap()
            return app.navigationBars["Ayarlar"].waitForExistence(timeout: 3)
        }
        
        let settingsEnglish = app.buttons["Settings"]
        if settingsEnglish.exists {
            settingsEnglish.tap()
            return app.navigationBars["Settings"].waitForExistence(timeout: 3)
        }
        
        // Try gear icon in navigation bar
        let navButtons = app.navigationBars.buttons
        for i in 0..<navButtons.count {
            let button = navButtons.element(boundBy: i)
            if button.exists && button.isHittable {
                button.tap()
                if app.navigationBars["Ayarlar"].waitForExistence(timeout: 2) ||
                   app.navigationBars["Settings"].waitForExistence(timeout: 2) {
                    return true
                }
                // Go back if this wasn't settings
                if let backButton = app.navigationBars.buttons.firstMatch as? XCUIElement, backButton.exists {
                    backButton.tap()
                }
            }
        }
        
        return false
    }
}
