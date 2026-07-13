import XCTest
@testable import PolyglotReader

final class TranslationContractTests: XCTestCase {
    func testLiteralPromptPreservesReferenceStructureAndForbidsCommentary() {
        let source = "First row | 42\nSecond row | 84"

        let prompt = TranslationPromptBuilder.literalPrompt(
            text: source,
            context: "An academic results table"
        )

        XCTAssertTrue(prompt.contains(source))
        XCTAssertTrue(prompt.contains("satır sonlarını, paragraf sırasını, liste ve tablo yapısını koru"))
        XCTAssertTrue(prompt.contains("yorum, açıklama, başlık, özet veya kaynak metni ekleme"))
        XCTAssertTrue(prompt.contains("yalnızca terminoloji seçimi için"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("metni analiz et"))
    }

    func testLiteralPromptKeepsLongSourceAndCodeFenceMarkersIntact() {
        let source = String(repeating: "table-cell ", count: 220) + "\n```reference```"

        let prompt = TranslationPromptBuilder.literalPrompt(text: source, context: nil)

        XCTAssertTrue(source.count > 2_000)
        XCTAssertTrue(prompt.contains(source))
        XCTAssertTrue(prompt.contains("```reference```"))
    }

    func testTranslationPolicyVersionSeparatesOldNonLiteralCacheEntries() {
        let oldKey = TranslationCacheKey.hash(sourceText: "hello world", targetLang: "tr")
        let literalKey = TranslationCacheKey.hash(
            sourceText: "hello world",
            targetLang: "tr",
            policyVersion: "literal-v2"
        )

        XCTAssertNotEqual(oldKey, literalKey)
    }

    func testLiteralTranslationCacheDistinguishesSourceLineStructure() {
        let tableLayout = TranslationCacheKey.hash(
            sourceText: "hello\nworld",
            targetLang: "tr",
            policyVersion: "literal-v2"
        )
        let inlineLayout = TranslationCacheKey.hash(
            sourceText: "hello world",
            targetLang: "tr",
            policyVersion: "literal-v2"
        )

        XCTAssertNotEqual(tableLayout, inlineLayout)
    }

    func testLiteralTranslationCacheNormalizesLineEndingEncoding() {
        let windows = TranslationCacheKey.hash(
            sourceText: "hello\r\nworld",
            targetLang: "tr",
            policyVersion: "literal-v2"
        )
        let unix = TranslationCacheKey.hash(
            sourceText: "hello\nworld",
            targetLang: "tr",
            policyVersion: "literal-v2"
        )

        XCTAssertEqual(windows, unix)
    }

    func testDetailedPromptUsesOnlyItsControlledResponseFields() {
        let prompt = TranslationPromptBuilder.detailedPrompt(text: "boundary", context: nil)

        XCTAssertTrue(prompt.contains("contextualTranslation"))
        XCTAssertTrue(prompt.contains("alternatives"))
        XCTAssertFalse(prompt.contains("detectedLanguage"))
        XCTAssertFalse(prompt.contains("Sadece translatedText"))
    }
}

final class AIResponseFormatterTests: XCTestCase {
    func testBreakAndInlineHTMLBecomeMarkdownWithoutVisibleTags() {
        let source = "Özet<br><br/><strong>Önemli</strong> ve <em>eğik</em>"

        let result = AIResponseFormatter.markdown(from: source)

        XCTAssertEqual(result, "Özet\n\n**Önemli** ve *eğik*")
        XCTAssertFalse(result.contains("<br"))
    }

    func testHTMLTableBecomesRenderableMarkdownTable() {
        let source = """
        <table>
          <tr><th>Ölçüt</th><th>Değer</th></tr>
          <tr><td>Hız</td><td><strong>42</strong></td></tr>
        </table>
        """

        let result = AIResponseFormatter.markdown(from: source)

        XCTAssertTrue(result.contains("| Ölçüt | Değer |"))
        XCTAssertTrue(result.contains("| --- | --- |"))
        XCTAssertTrue(result.contains("| Hız | **42** |"))
        XCTAssertFalse(result.contains("<table>"))
    }

    func testEntitiesAreDecodedAndUnknownTagsAreRemoved() {
        let source = "<p>A &amp; B&nbsp;</p><script>ignored()</script><p>C</p>"

        let result = AIResponseFormatter.markdown(from: source)

        XCTAssertEqual(result, "A & B\n\nC")
        XCTAssertFalse(result.contains("script"))
    }
}
