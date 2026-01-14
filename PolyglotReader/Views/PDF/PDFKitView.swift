import SwiftUI
import PDFKit

// MARK: - PDFView Extension
extension PDFView {
    var scrollView: UIScrollView? {
        subviews.first { $0 is UIScrollView } as? UIScrollView
    }
}

// MARK: - PDFKitView
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    @Binding var currentPage: Int
    var isQuickTranslationMode: Bool = false
    var bottomInset: CGFloat = 0
    var annotations: [Annotation] = []
    
    // Reading Progress
    var initialScrollPosition: CGPoint?
    var onProgressChange: ((Int, CGPoint, CGFloat) -> Void)?

    // Callbacks
    var onSelection: ((String, CGRect, Int, [CGRect]) -> Void)?  // pdfRects added for PDF coordinate system
    var onImageSelection: ((PDFImageInfo) -> Void)?
    var onRenderComplete: (() -> Void)?
    var onTap: (() -> Void)?
    var onAnnotationTap: ((Annotation) -> Void)?

    func makeCoordinator() -> PDFKitCoordinator {
        PDFKitCoordinator(self)
    }

    func makeUIView(context: Context) -> CustomPDFView {
        let pdfView = CustomPDFView()
        configurePdfView(pdfView)
        configureCoordinator(context, pdfView)
        attachGestures(to: pdfView, coordinator: context.coordinator)
        registerObservers(for: pdfView, coordinator: context.coordinator)
        return pdfView
    }

    func updateUIView(_ pdfView: CustomPDFView, context: Context) {
        context.coordinator.parent = self
        pdfView.isQuickTranslationMode = isQuickTranslationMode
        updateInsetsIfNeeded(for: pdfView)
        updateDocumentIfNeeded(pdfView, context: context)
        restoreStateIfNeeded(pdfView, coordinator: context.coordinator)
        syncCurrentPage(pdfView)
        applyAnnotationsIfNeeded(pdfView, coordinator: context.coordinator)
    }

    private func configurePdfView(_ pdfView: CustomPDFView) {
        pdfView.alpha = 0
        pdfView.autoScales = true
        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 4.0
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false, withViewOptions: nil)
        pdfView.backgroundColor = .systemGray6
        pdfView.pageShadowsEnabled = true
        pdfView.isUserInteractionEnabled = true
    }

    private func configureCoordinator(_ context: Context, _ pdfView: CustomPDFView) {
        context.coordinator.onRenderComplete = onRenderComplete
        context.coordinator.pdfView = pdfView
        
        // Set Scroll Delegate
        pdfView.scrollView?.delegate = context.coordinator
    }

    private func attachGestures(to pdfView: CustomPDFView, coordinator: PDFKitCoordinator) {
        let tapGesture = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(PDFKitCoordinator.handleTap(_:))
        )
        tapGesture.delegate = coordinator
        pdfView.addGestureRecognizer(tapGesture)

        pdfView.onTouchStateChanged = { [weak coordinator] isTouching in
            if !isTouching {
                coordinator?.handleTouchEnded()
            }
        }

        let longPressGesture = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(PDFKitCoordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.35
        longPressGesture.delegate = coordinator
        pdfView.addGestureRecognizer(longPressGesture)
        coordinator.customLongPressGesture = longPressGesture
    }

    private func registerObservers(for pdfView: CustomPDFView, coordinator: PDFKitCoordinator) {
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(PDFKitCoordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(PDFKitCoordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(PDFKitCoordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
    }

    private func updateInsetsIfNeeded(for pdfView: CustomPDFView) {
        guard let scrollView = pdfView.scrollView else { return }
        guard scrollView.contentInset.bottom != bottomInset else { return }

        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        scrollView.scrollIndicatorInsets = scrollView.contentInset
    }

    private func updateDocumentIfNeeded(_ pdfView: CustomPDFView, context: Context) {
        guard let newDocument = document else {
            if pdfView.document != nil {
                pdfView.document = nil
            }
            return
        }
        guard pdfView.document !== newDocument else { return }

        pdfView.alpha = 0
        pdfView.document = newDocument

        if let firstPage = newDocument.page(at: 0) {
            pdfView.go(to: firstPage)
        }

        updateInsetsIfNeeded(for: pdfView)
        animateDocumentLoad(pdfView, coordinator: context.coordinator)
    }

    private func animateDocumentLoad(_ pdfView: CustomPDFView, coordinator: PDFKitCoordinator) {
        // Layout'u hemen zorla - büyük PDF'lerde bile hızlı olmalı
        pdfView.layoutIfNeeded()

        // Minimal delay sonra fade-in animasyonu başlat
        // Eski: 0.3 + 0.2 + 0.25 = 0.75s toplam bekleme
        // Yeni: 0.1 + 0.2 = 0.3s toplam - 60% daha hızlı
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                pdfView.alpha = 1
            } completion: { _ in
                coordinator.onRenderComplete?()
            }
        }
    }

    private func syncCurrentPage(_ pdfView: CustomPDFView) {
        // PDFView'deki mevcut görüntülenen sayfayı al
        guard let currentDoc = pdfView.document,
              let displayedPage = pdfView.currentPage else { return }
        
        let displayedPageIndex = currentDoc.index(for: displayedPage) + 1
        
        // Eğer binding'deki sayfa ile görüntülenen sayfa aynıysa, bir şey yapma
        // Bu, kullanıcının scroll ile sayfa değiştirmesinden sonra gereksiz navigasyonu engeller
        if displayedPageIndex == currentPage { return }
        
        // Eğer binding'deki sayfa farklıysa VE bu programatik bir değişiklikse (örn. PageSpinner'dan),
        // o zaman sayfaya git
        // Bunu anlamak için: binding değişikliği Coordinator'ın pageChanged'inden gelmediyse
        // (yani kullanıcı scroll yapmadıysa) o zaman programatik bir istektir
        guard let targetPage = currentDoc.page(at: currentPage - 1) else { return }
        pdfView.go(to: targetPage)
    }

    private func restoreStateIfNeeded(_ pdfView: CustomPDFView, coordinator: PDFKitCoordinator) {
        guard let initialPos = initialScrollPosition,
              !coordinator.hasRestoredInitialPosition,
              let document = pdfView.document else { return }

        guard let page = document.page(at: currentPage - 1) else { return }
        
        let dest = PDFDestination(page: page, at: initialPos)
        // Zoom restoring logic handles by PDFKit naturally if destination has zoom?
        // PDFDestination point + zoom? 
        // PDFDestination(page:at:) uses kPDFDestinationPage/Point.
        
        // We might need to ensure scale is set if needed, but viewModel binds scale?
        // Let's assume point restoration is key.
        
        // Use a slight delay to ensure layout is ready?
        DispatchQueue.main.async {
            pdfView.go(to: dest)
        }
        
        coordinator.hasRestoredInitialPosition = true
    }

    private func applyAnnotationsIfNeeded(_ pdfView: CustomPDFView, coordinator: PDFKitCoordinator) {
        guard let doc = pdfView.document else { return }
        coordinator.applyAnnotationUpdate(to: doc, annotations: annotations)
    }
}
