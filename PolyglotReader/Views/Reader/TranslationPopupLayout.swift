import CoreGraphics
import Foundation

// MARK: - Layout Math

/// Pure positioning math for QuickTranslationPopup.
/// Free of SwiftUI so flip/clamp behavior is unit-testable.
enum TranslationPopupLayout {
    /// Height of the drag handle area above the content.
    static let handleHeight: CGFloat = 28
    /// Vertical gap between the selection rect and the popup edge.
    static let selectionGap: CGFloat = 16
    /// Minimum padding kept between the popup and the container edges.
    static let edgePadding: CGFloat = 8

    /// Popup width for a given container (mirrors the old UIScreen-based sizing).
    static func popupWidth(for containerSize: CGSize) -> CGFloat {
        let isLandscape = containerSize.width > containerSize.height
        if isLandscape {
            // Yatay modda genişliğin %70'i, max 600
            return min(containerSize.width * 0.7, 600)
        }
        // Dikey modda genişlik - 40, max 340
        return min(containerSize.width - 40, 340)
    }

    /// Center position for the popup: below the selection when it fits,
    /// otherwise flipped ABOVE the selection; always clamped inside the container.
    static func basePosition(selectionRect: CGRect, popupSize: CGSize, container: CGRect) -> CGPoint {
        let halfHeight = popupSize.height / 2
        let belowY = selectionRect.maxY + selectionGap + halfHeight
        let aboveY = selectionRect.minY - selectionGap - halfHeight

        // Flip above when the popup would poke past the bottom edge.
        let fitsBelow = belowY + halfHeight + edgePadding <= container.maxY
        let proposedY = fitsBelow ? belowY : aboveY

        return clamp(
            CGPoint(x: selectionRect.midX, y: proposedY),
            popupSize: popupSize,
            container: container
        )
    }

    /// Clamps a center point so the popup stays fully inside the container.
    static func clamp(_ center: CGPoint, popupSize: CGSize, container: CGRect) -> CGPoint {
        CGPoint(
            x: clampValue(
                center.x,
                lower: container.minX + popupSize.width / 2 + edgePadding,
                upper: container.maxX - popupSize.width / 2 - edgePadding
            ),
            y: clampValue(
                center.y,
                lower: container.minY + popupSize.height / 2 + edgePadding,
                upper: container.maxY - popupSize.height / 2 - edgePadding
            )
        )
    }

    /// Clamps a drag offset so base + offset keeps the popup on screen.
    static func clampedOffset(
        _ proposed: CGSize,
        base: CGPoint,
        popupSize: CGSize,
        container: CGRect
    ) -> CGSize {
        let target = CGPoint(x: base.x + proposed.width, y: base.y + proposed.height)
        let clamped = clamp(target, popupSize: popupSize, container: container)
        return CGSize(width: clamped.x - base.x, height: clamped.y - base.y)
    }

    private static func clampValue(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        // Popup larger than the container: center it instead of producing an inverted range.
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

// MARK: - Layout Context

/// Snapshot of everything the popup needs to place and clamp itself.
/// `selectionRect` must already be converted to the container's local space.
struct TranslationPopupLayoutContext {
    let containerSize: CGSize
    let selectionRect: CGRect
    let scale: CGFloat

    var container: CGRect { CGRect(origin: .zero, size: containerSize) }
    var isLandscape: Bool { containerSize.width > containerSize.height }
    var popupWidth: CGFloat { TranslationPopupLayout.popupWidth(for: containerSize) }

    /// Unscaled content height (portrait taller than landscape).
    var baseContentHeight: CGFloat { isLandscape ? 120 : 180 }

    /// Content max height before scaleEffect (matches the legacy double-scaling behavior).
    var contentMaxHeight: CGFloat { baseContentHeight * scale }

    /// Effective on-screen size after scaleEffect is applied.
    var scaledSize: CGSize {
        CGSize(
            width: popupWidth * scale,
            height: (TranslationPopupLayout.handleHeight + contentMaxHeight) * scale
        )
    }

    /// Flip-aware, clamped center position for the popup.
    var basePosition: CGPoint {
        TranslationPopupLayout.basePosition(
            selectionRect: selectionRect,
            popupSize: scaledSize,
            container: container
        )
    }

    /// Same context at a different pinch scale (used to re-clamp after zooming).
    func rescaled(to newScale: CGFloat) -> TranslationPopupLayoutContext {
        TranslationPopupLayoutContext(
            containerSize: containerSize,
            selectionRect: selectionRect,
            scale: newScale
        )
    }
}
