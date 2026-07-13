import Combine
import Foundation

/// The four beats in the unauthenticated Corio Docs product story.
enum EntryDemoPhase: Int, CaseIterable, Identifiable {
    case library
    case reader
    case translation
    case annotation

    var id: Int { rawValue }

    var next: EntryDemoPhase {
        let phases = Self.allCases
        let nextIndex = (rawValue + 1) % phases.count
        return phases[nextIndex]
    }
}

/// Identifies whether a demo change came from choreography or direct manipulation.
enum EntryDemoSelectionSource: Equatable {
    case automatic
    case user
}

/// Owns entry-demo choreography so the SwiftUI view remains presentation-only.
@MainActor
final class EntryExperienceViewModel: ObservableObject {
    @Published private(set) var phase: EntryDemoPhase
    @Published private(set) var isAutoPlaying: Bool

    private var reduceMotion = false
    private var isSceneActive = true
    private var autoPlayTask: Task<Void, Never>?

    init(phase: EntryDemoPhase = .library) {
        self.phase = phase
        self.isAutoPlaying = true
    }

    deinit {
        autoPlayTask?.cancel()
    }

    var progress: Double {
        guard EntryDemoPhase.allCases.count > 1 else { return 0 }
        return Double(phase.rawValue) / Double(EntryDemoPhase.allCases.count - 1)
    }

    func advance() {
        select(phase.next, source: .automatic)
    }

    func select(_ phase: EntryDemoPhase, source: EntryDemoSelectionSource) {
        self.phase = phase
        if source == .user {
            pauseAutoPlay()
        }
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        if enabled {
            pauseAutoPlay()
        }
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if !active {
            pauseAutoPlay()
        }
    }

    func pauseAutoPlay() {
        isAutoPlaying = false
        autoPlayTask?.cancel()
        autoPlayTask = nil
    }

    func resumeAutoPlay() {
        guard !reduceMotion, isSceneActive else { return }
        isAutoPlaying = true
    }

    func startAutoPlayLoop(intervalNanoseconds: UInt64 = 4_800_000_000) {
        autoPlayTask?.cancel()
        guard isAutoPlaying, !reduceMotion, isSceneActive else { return }

        autoPlayTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }

                guard let self, self.isAutoPlaying, self.isSceneActive, !self.reduceMotion else {
                    return
                }
                self.advance()
            }
        }
    }
}
