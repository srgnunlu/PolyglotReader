import UIKit
import PDFKit

// MARK: - Professional Magnifier View
class MagnifierView: UIView {
    // MARK: - Configuration
    private let diameter: CGFloat = 100
    private let zoomFactor: CGFloat = 1.6
    private let verticalOffset: CGFloat = -60

    // MARK: - State
    private weak var targetPDFView: PDFView?
    private var focusPage: PDFPage?
    private var focusPointInPage: CGPoint = .zero
    private var activeSelection: PDFSelection?

    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        backgroundColor = .white
        layer.cornerRadius = diameter / 2
        layer.masksToBounds = true
        layer.borderWidth = 3
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
        isHidden = true
        isUserInteractionEnabled = false
    }

    // MARK: - Public API
    func show(at viewPoint: CGPoint, pagePoint: CGPoint, page: PDFPage, selection: PDFSelection?, in pdfView: PDFView) {
        self.targetPDFView = pdfView
        self.focusPage = page
        self.focusPointInPage = pagePoint
        self.activeSelection = selection

        var adjustedCenter = CGPoint(x: viewPoint.x, y: viewPoint.y + verticalOffset)

        if let superview = superview {
            let halfWidth = diameter / 2
            let halfHeight = diameter / 2
            adjustedCenter.x = max(halfWidth, min(superview.bounds.width - halfWidth, adjustedCenter.x))
            adjustedCenter.y = max(halfHeight, min(superview.bounds.height - halfHeight, adjustedCenter.y))
        }

        self.center = adjustedCenter
        self.isHidden = false
        self.setNeedsDisplay()
    }

    func dismiss() {
        isHidden = true
        focusPage = nil
        activeSelection = nil
        targetPDFView = nil
    }

    // MARK: - Rendering
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let page = focusPage else { return }

        UIColor.white.setFill()
        ctx.fill(rect)

        ctx.saveGState()

        let centerX = rect.width / 2
        let centerY = rect.height / 2

        ctx.translateBy(x: centerX, y: centerY)
        ctx.scaleBy(x: zoomFactor, y: zoomFactor)
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.translateBy(x: -focusPointInPage.x, y: -focusPointInPage.y)

        page.draw(with: .mediaBox, to: ctx)

        if let selection = activeSelection {
            UIColor.systemBlue.withAlphaComponent(0.35).setFill()
            for lineSelection in selection.selectionsByLine() {
                let lineBounds = lineSelection.bounds(for: page)
                if !lineBounds.isNull && !lineBounds.isInfinite {
                    ctx.fill(lineBounds)
                }
            }
        }

        ctx.restoreGState()
    }
}

// MARK: - Selection Overlay View
class SelectionOverlay: UIView {
    weak var pdfView: PDFView?
    var selection: PDFSelection?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    func update(selection: PDFSelection?, pdfView: PDFView) {
        self.selection = selection
        self.pdfView = pdfView
        self.frame = pdfView.bounds
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let selection = selection,
              let pdfView = pdfView,
              let context = UIGraphicsGetCurrentContext() else { return }

        let selectionsByLine = selection.selectionsByLine()

        context.saveGState()

        // Highlights
        UIColor.systemBlue.withAlphaComponent(0.3).setFill()
        for line in selectionsByLine {
            guard let page = line.pages.first else { continue }
            let pdfRect = line.bounds(for: page)
            let viewRect = pdfView.convert(pdfRect, from: page)

            if !viewRect.isNull && !viewRect.isInfinite {
                context.fill(viewRect)
            }
        }

        // Handles
        drawHandles(context: context, selectionsByLine: selectionsByLine, pdfView: pdfView)

        context.restoreGState()
    }

    private func drawHandles(context: CGContext, selectionsByLine: [PDFSelection], pdfView: PDFView) {
        UIColor.systemBlue.setStroke()
        UIColor.systemBlue.setFill()
        let handleRadius: CGFloat = 5.0
        let lineWidth: CGFloat = 2.0

        if let first = selectionsByLine.first, let page = first.pages.first {
            drawHandle(
                context: context,
                selection: first,
                page: page,
                pdfView: pdfView,
                isStart: true,
                radius: handleRadius,
                width: lineWidth
            )
        }

        if let last = selectionsByLine.last, let page = last.pages.first {
            drawHandle(
                context: context,
                selection: last,
                page: page,
                pdfView: pdfView,
                isStart: false,
                radius: handleRadius,
                width: lineWidth
            )
        }
    }

    private func drawHandle(
        context: CGContext,
        selection: PDFSelection,
        page: PDFPage,
        pdfView: PDFView,
        isStart: Bool,
        radius: CGFloat,
        width: CGFloat
    ) {
        let pdfRect = selection.bounds(for: page)
        let viewRect = pdfView.convert(pdfRect, from: page)
        guard !viewRect.isNull && !viewRect.isInfinite else { return }

        let startPoint = CGPoint(x: isStart ? viewRect.minX : viewRect.maxX, y: viewRect.minY)
        let endPoint = CGPoint(x: isStart ? viewRect.minX : viewRect.maxX, y: viewRect.maxY)

        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()

        let ovalY = isStart ? startPoint.y - radius * 2 : endPoint.y
        let circleRect = CGRect(x: endPoint.x - radius, y: ovalY, width: radius * 2, height: radius * 2)
        let circlePath = UIBezierPath(ovalIn: circleRect)
        circlePath.fill()
    }
}
