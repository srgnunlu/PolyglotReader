import Foundation
import PDFKit
import CoreGraphics

// MARK: - Scan Context

/// Mutable state shared with the C scanner callbacks while walking a page's
/// content stream. Tracks the graphics state (CTM) so each image XObject's
/// unit square can be mapped into page coordinates.
private final class XObjectScanContext {
    var ctm = CGAffineTransform.identity
    var ctmStack: [CGAffineTransform] = []
    var resources: CGPDFDictionaryRef?
    var imageRects: [CGRect] = []
    var formDepth = 0
    /// Current content stream; needed as the parent when recursing into forms.
    var currentContentStream: CGPDFContentStreamRef?
}

// MARK: - Scanner Callbacks
// C function pointers cannot capture state, so the context travels through
// the scanner's opaque `info` pointer.

private let saveStateCallback: CGPDFOperatorCallback = { _, info in
    guard let info else { return }
    let context = Unmanaged<XObjectScanContext>.fromOpaque(info).takeUnretainedValue()
    context.ctmStack.append(context.ctm)
}

private let restoreStateCallback: CGPDFOperatorCallback = { _, info in
    guard let info else { return }
    let context = Unmanaged<XObjectScanContext>.fromOpaque(info).takeUnretainedValue()
    if !context.ctmStack.isEmpty {
        context.ctm = context.ctmStack.removeLast()
    }
}

private let concatMatrixCallback: CGPDFOperatorCallback = { scanner, info in
    guard let info else { return }
    let context = Unmanaged<XObjectScanContext>.fromOpaque(info).takeUnretainedValue()
    // Operands are popped off the stack in reverse order: f e d c b a.
    var values = [CGPDFReal](repeating: 0, count: 6)
    for index in stride(from: 5, through: 0, by: -1) {
        var value: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &value) else { return }
        values[index] = value
    }
    let matrix = CGAffineTransform(
        a: values[0],
        b: values[1],
        c: values[2],
        d: values[3],
        tx: values[4],
        ty: values[5]
    )
    context.ctm = matrix.concatenating(context.ctm)
}

private let drawXObjectCallback: CGPDFOperatorCallback = { scanner, info in
    guard let info else { return }
    let context = Unmanaged<XObjectScanContext>.fromOpaque(info).takeUnretainedValue()

    var name: UnsafePointer<Int8>?
    guard CGPDFScannerPopName(scanner, &name), let name,
          let resources = context.resources else { return }

    var xObjects: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else { return }

    var stream: CGPDFStreamRef?
    guard CGPDFDictionaryGetStream(xObjects, name, &stream), let stream,
          let streamDict = CGPDFStreamGetDictionary(stream) else { return }

    var subtypeName: UnsafePointer<Int8>?
    guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtypeName), let subtypeName else { return }

    switch String(cString: subtypeName) {
    case "Image":
        // An image XObject is always drawn into the unit square, mapped by the CTM.
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(context.ctm)
        context.imageRects.append(rect.standardized)
    case "Form":
        PDFImageXObjectLocator.scanForm(stream, dictionary: streamDict, context: context)
    default:
        break
    }
}

// MARK: - PDF Image XObject Locator

/// Finds the exact bounds of raster images placed on a PDF page by scanning
/// the page's content stream (q/Q/cm/Do operators). Unlike Vision-based edge
/// detection this returns the true placement rectangles, so multi-part
/// figures are not fragmented and captions are not swallowed.
final class PDFImageXObjectLocator {
    static let shared = PDFImageXObjectLocator()

    private init() {}

    /// Returns the bounds (mediaBox/page space) of every raster image drawn
    /// on the page, including images nested inside form XObjects.
    func imageRects(on page: PDFPage) -> [CGRect] {
        guard let pageRef = page.pageRef,
              let pageDict = pageRef.dictionary else { return [] }

        let context = XObjectScanContext()
        context.resources = Self.resolveResources(startingAt: pageDict)

        guard let table = CGPDFOperatorTableCreate() else { return [] }
        Self.registerCallbacks(on: table)

        let contentStream = CGPDFContentStreamCreateWithPage(pageRef)
        context.currentContentStream = contentStream
        let info = Unmanaged.passUnretained(context).toOpaque()
        let scanner = CGPDFScannerCreate(contentStream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contentStream)
        CGPDFOperatorTableRelease(table)

        return context.imageRects
    }

    // MARK: - Form Recursion

    /// Scans a form XObject's own content stream, composing the form's Matrix
    /// into the current CTM. Depth-limited as a guard against pathological
    /// self-referencing forms.
    fileprivate static func scanForm(
        _ stream: CGPDFStreamRef,
        dictionary: CGPDFDictionaryRef,
        context: XObjectScanContext
    ) {
        guard context.formDepth < 4,
              let parentContentStream = context.currentContentStream else { return }

        let savedCTM = context.ctm
        let savedStack = context.ctmStack
        let savedResources = context.resources

        if let matrix = formMatrix(from: dictionary) {
            context.ctm = matrix.concatenating(context.ctm)
        }
        var formResources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dictionary, "Resources", &formResources), let formResources {
            context.resources = formResources
        }

        // The C API requires non-optional resources; without any resources
        // dictionary a nested Do could not be resolved anyway.
        if let resources = context.resources, let table = CGPDFOperatorTableCreate() {
            registerCallbacks(on: table)
            context.formDepth += 1
            context.ctmStack = []
            let contentStream = CGPDFContentStreamCreateWithStream(stream, resources, parentContentStream)
            context.currentContentStream = contentStream
            let info = Unmanaged.passUnretained(context).toOpaque()
            let scanner = CGPDFScannerCreate(contentStream, table, info)
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            CGPDFContentStreamRelease(contentStream)
            CGPDFOperatorTableRelease(table)
            context.formDepth -= 1
        }

        context.currentContentStream = parentContentStream
        context.ctm = savedCTM
        context.ctmStack = savedStack
        context.resources = savedResources
    }

    // MARK: - Helpers

    private static func registerCallbacks(on table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q", saveStateCallback)
        CGPDFOperatorTableSetCallback(table, "Q", restoreStateCallback)
        CGPDFOperatorTableSetCallback(table, "cm", concatMatrixCallback)
        CGPDFOperatorTableSetCallback(table, "Do", drawXObjectCallback)
    }

    private static func formMatrix(from dictionary: CGPDFDictionaryRef) -> CGAffineTransform? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array,
              CGPDFArrayGetCount(array) == 6 else { return nil }

        var values = [CGPDFReal](repeating: 0, count: 6)
        for index in 0..<6 {
            var value: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
            values[index] = value
        }
        return CGAffineTransform(
            a: values[0],
            b: values[1],
            c: values[2],
            d: values[3],
            tx: values[4],
            ty: values[5]
        )
    }

    /// Resources may be inherited from an ancestor Pages node, so walk the
    /// Parent chain until a Resources dictionary is found.
    private static func resolveResources(startingAt pageDict: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var current: CGPDFDictionaryRef? = pageDict
        var depth = 0
        while let dict = current, depth < 32 {
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources {
                return resources
            }
            var parent: CGPDFDictionaryRef?
            current = CGPDFDictionaryGetDictionary(dict, "Parent", &parent) ? parent : nil
            depth += 1
        }
        return nil
    }
}
