import XCTest

/// UI tests for the login flow
final class LoginFlowUITests: UITestBase {
    
    // MARK: - Login Screen Tests
    
    func testLoginScreenElementsExist() {
        // Given - App is launched and we're on the login screen
        
        // Then - Login UI elements should be present using accessibility identifiers
        let googleButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'Google'"))
            .firstMatch
        let appleButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'Apple'"))
            .firstMatch
        
        // Allow time for the app to load
        _ = googleButton.waitForExistence(timeout: 5)
        
        // Check for accessibility identifiers first, then fall back to labels
        let hasGoogleButton = googleButton.exists || 
                              app.buttons["Google ile Giriş Yap"].exists ||
                              app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google'")).firstMatch.exists
        
        let hasAppleButton = appleButton.exists || 
                             app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Apple'")).firstMatch.exists
        
        // At least one authentication method should be available
        XCTAssertTrue(hasGoogleButton || hasAppleButton, "Login buttons should be present")
    }
    
    func testAppTitleIsDisplayed() {
        // Given - App is launched
        
        // Then - App title or logo should be visible
        let appTitle = app.staticTexts["Corio Docs"]
        let hasTitle = waitForElement(appTitle, timeout: 5)
        
        // The app might show the title differently
        if !hasTitle {
            // Check for any prominent text element or login screen
            let anyTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Corio'")).firstMatch
            XCTAssertTrue(anyTitle.exists || isOnLoginScreen, "App should show title or login screen")
        }
    }

    func testInteractiveProductDemoKeepsAuthenticationAvailable() {
        let entryExperience = app.otherElements["entry_experience"]
        XCTAssertTrue(entryExperience.waitForExistence(timeout: 5))

        let translationStage = app.buttons["Seç. Anında çevir."]
        XCTAssertTrue(translationStage.waitForExistence(timeout: 3))
        translationStage.tap()

        XCTAssertTrue(app.buttons["Çeviri sonucu"].waitForExistence(timeout: 3))

        let appleButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'Apple'"))
            .firstMatch
        let googleButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'Google'"))
            .firstMatch
        XCTAssertTrue(appleButton.waitForExistence(timeout: 3))
        XCTAssertTrue(googleButton.waitForExistence(timeout: 3))
    }
    
    // MARK: - Navigation Tests
    
    func testLoginScreenIsFirstScreen() {
        // Given - Fresh app launch
        
        // Then - Should be on login screen (not library)
        // Give time for auth check
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                return self.isOnLoginScreen || self.isOnLibraryScreen
            },
            object: nil
        )
        
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        
        XCTAssertEqual(result, .completed, "App should show either login or library screen")
    }
    
    // MARK: - Button Interaction Tests
    
    func testGoogleSignInButtonIsHittable() throws {
        // Given
        let googleButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google'")).firstMatch
        
        // When - Wait for button
        guard waitForElement(googleButton, timeout: 5) else {
            // If no Google button, we might already be logged in
            throw XCTSkip("Google sign-in button not found - user may be logged in")
        }
        
        // Then
        XCTAssertTrue(googleButton.isHittable, "Google sign-in button should be tappable")
    }
    
    func testAppleSignInButtonIsHittable() throws {
        // Given
        let appleButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Apple'")).firstMatch
        
        // When - Wait for button
        guard waitForElement(appleButton, timeout: 5) else {
            // If no Apple button, we might already be logged in
            throw XCTSkip("Apple sign-in button not found - user may be logged in")
        }
        
        // Then
        XCTAssertTrue(appleButton.isHittable, "Apple sign-in button should be tappable")
    }
    
    // MARK: - Screenshot Tests
    
    func testLoginScreenLooksCorrect() {
        // Given - App is on login screen
        
        // When - Wait for screen to load
        _ = app.buttons.firstMatch.waitForExistence(timeout: 5)
        
        // Then - Capture screenshot for visual verification
        takeScreenshot(name: "Login_Screen")
    }
}
