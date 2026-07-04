import XCTest
@testable import PolyglotReader

/// Unit tests for the translation cache key (cross-platform parity critical)
/// and the in-memory LRU layer.
final class TranslationCacheServiceTests: XCTestCase {
    // MARK: - Normalization

    func testNormalizeTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(TranslationCacheKey.normalize("  hello world  "), "hello world")
    }

    func testNormalizeCollapsesInternalWhitespaceRuns() {
        XCTAssertEqual(TranslationCacheKey.normalize("hello   \n\t world"), "hello world")
    }

    func testNormalizeHandlesNewlinesAndTabsOnly() {
        XCTAssertEqual(TranslationCacheKey.normalize("\n\t \n"), "")
    }

    func testNormalizeDoesNotLowercase() {
        XCTAssertEqual(TranslationCacheKey.normalize("Hello World"), "Hello World")
    }

    // MARK: - Hash (parity vectors — MUST match the web implementation)

    /// SHA-256("tr::hello world") — cross-check this exact hex on the web side.
    func testHashKnownVector() {
        XCTAssertEqual(
            TranslationCacheKey.hash(sourceText: "hello world", targetLang: "tr"),
            "dba8b309624ef8185a8c080ba72abd5b01f9a11ae3f163d20482089466852865"
        )
    }

    /// SHA-256("tr::merhaba dünya") — verifies UTF-8 (non-ASCII) encoding parity.
    func testHashKnownVectorUnicode() {
        XCTAssertEqual(
            TranslationCacheKey.hash(sourceText: "merhaba dünya", targetLang: "tr"),
            "74454167503b03111822cebd9d014c816ab40344dd75823606c6b4ac096a0338"
        )
    }

    func testHashIsWhitespaceInsensitive() {
        let messy = TranslationCacheKey.hash(sourceText: "  hello\n\t  world ", targetLang: "tr")
        let clean = TranslationCacheKey.hash(sourceText: "hello world", targetLang: "tr")
        XCTAssertEqual(messy, clean)
    }

    func testHashChangesWithTargetLanguage() {
        let turkish = TranslationCacheKey.hash(sourceText: "hello world", targetLang: "tr")
        let english = TranslationCacheKey.hash(sourceText: "hello world", targetLang: "en")
        XCTAssertNotEqual(turkish, english)
    }

    // MARK: - LRU Cache

    func testLRUStoresAndReturnsValues() {
        var cache = TranslationLRUCache(capacity: 3)
        cache.insert("bir", forKey: "a")
        XCTAssertEqual(cache.value(forKey: "a"), "bir")
        XCTAssertNil(cache.value(forKey: "missing"))
    }

    func testLRUEvictsLeastRecentlyUsedOnOverflow() {
        var cache = TranslationLRUCache(capacity: 2)
        cache.insert("1", forKey: "a")
        cache.insert("2", forKey: "b")
        cache.insert("3", forKey: "c") // evicts "a"

        XCTAssertNil(cache.value(forKey: "a"))
        XCTAssertEqual(cache.value(forKey: "b"), "2")
        XCTAssertEqual(cache.value(forKey: "c"), "3")
        XCTAssertEqual(cache.count, 2)
    }

    func testLRUReadRefreshesRecency() {
        var cache = TranslationLRUCache(capacity: 2)
        cache.insert("1", forKey: "a")
        cache.insert("2", forKey: "b")
        _ = cache.value(forKey: "a") // "a" becomes most recent
        cache.insert("3", forKey: "c") // evicts "b", not "a"

        XCTAssertEqual(cache.value(forKey: "a"), "1")
        XCTAssertNil(cache.value(forKey: "b"))
    }

    func testLRUUpdatingExistingKeyDoesNotEvict() {
        var cache = TranslationLRUCache(capacity: 2)
        cache.insert("1", forKey: "a")
        cache.insert("2", forKey: "b")
        cache.insert("yeni", forKey: "a") // update, no overflow

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.value(forKey: "a"), "yeni")
        XCTAssertEqual(cache.value(forKey: "b"), "2")
    }

    func testLRUEnforcesMinimumCapacityOfOne() {
        var cache = TranslationLRUCache(capacity: 0)
        cache.insert("1", forKey: "a")
        cache.insert("2", forKey: "b")

        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.value(forKey: "b"), "2")
    }
}
