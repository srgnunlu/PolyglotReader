import SwiftUI

// MARK: - Share Support

/// `.sheet(item:)` Identifiable ister; paylaşılacak geçici dosya URL'ini sarar.
/// Paylaşım sheet'i için DebugLogsView'daki mevcut `ShareSheet` sarmalayıcısı kullanılır.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Card -> Reader Zoom Transition (iOS 18+)
/// The reader opens by zooming out of the tapped card. iOS 17 keeps the
/// standard cover presentation — a designed default, not a broken fallback.
extension View {
    @ViewBuilder
    func readerZoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func readerZoomTransition(sourceID: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - Card Scroll Transition
/// Cards fade+scale slightly at the viewport edges — depth without noise.
private struct LibraryCardScrollTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scrollTransition(.interactive) { [reduceMotion] view, phase in
            view
                .opacity(!reduceMotion && !phase.isIdentity ? 0.55 : 1)
                .scaleEffect(!reduceMotion && !phase.isIdentity ? 0.96 : 1)
        }
    }
}

extension View {
    func libraryCardScrollTransition() -> some View {
        modifier(LibraryCardScrollTransition())
    }
}
