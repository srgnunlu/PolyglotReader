import XCTest
@testable import PolyglotReader

/// The unauthenticated entry demo must stay predictable under autoplay,
/// direct manipulation, and accessibility preferences.
@MainActor
final class EntryExperienceViewModelTests: XCTestCase {
    func testInitialStateStartsAtLibraryAndAutoplays() {
        let sut = EntryExperienceViewModel()

        XCTAssertEqual(sut.phase, .library)
        XCTAssertTrue(sut.isAutoPlaying)
        XCTAssertEqual(sut.progress, 0)
    }

    func testAdvanceCyclesThroughTheProductStory() {
        let sut = EntryExperienceViewModel()

        sut.advance()
        XCTAssertEqual(sut.phase, .reader)

        sut.advance()
        XCTAssertEqual(sut.phase, .translation)

        sut.advance()
        XCTAssertEqual(sut.phase, .annotation)

        sut.advance()
        XCTAssertEqual(sut.phase, .library)
    }

    func testUserSelectionPausesAutoplayAndCanResume() {
        let sut = EntryExperienceViewModel()

        sut.select(.translation, source: .user)

        XCTAssertEqual(sut.phase, .translation)
        XCTAssertFalse(sut.isAutoPlaying)
        XCTAssertEqual(sut.progress, 2.0 / 3.0, accuracy: 0.001)

        sut.resumeAutoPlay()
        XCTAssertTrue(sut.isAutoPlaying)
    }

    func testReduceMotionStopsAutoplayUntilPreferenceIsDisabled() {
        let sut = EntryExperienceViewModel()

        sut.setReduceMotion(true)
        XCTAssertFalse(sut.isAutoPlaying)

        sut.resumeAutoPlay()
        XCTAssertFalse(sut.isAutoPlaying)

        sut.setReduceMotion(false)
        sut.resumeAutoPlay()
        XCTAssertTrue(sut.isAutoPlaying)
    }

    func testInactiveSceneStopsAutoplayAndBlocksResume() {
        let sut = EntryExperienceViewModel()

        sut.setSceneActive(false)
        XCTAssertFalse(sut.isAutoPlaying)

        sut.resumeAutoPlay()
        XCTAssertFalse(sut.isAutoPlaying)

        sut.setSceneActive(true)
        sut.resumeAutoPlay()
        XCTAssertTrue(sut.isAutoPlaying)
    }

    func testAutomaticSelectionDoesNotPauseAutoplay() {
        let sut = EntryExperienceViewModel()

        sut.select(.reader, source: .automatic)

        XCTAssertEqual(sut.phase, .reader)
        XCTAssertTrue(sut.isAutoPlaying)
    }
}
