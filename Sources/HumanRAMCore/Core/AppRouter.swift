import Foundation

/// Navigation seam between portable core logic/views and the host app's
/// presentation layer. The macOS app installs window-based handlers at launch;
/// an iOS host will install sheet-based ones.
public final class AppRouter {
    public static let shared = AppRouter()

    public var presentDailyScan: () -> Void = {}
    public var presentNotesReview: () -> Void = {}
    public var presentEditItem: (UUID) -> Void = { _ in }
    public var presentGuide: () -> Void = {}
    public var dismissActiveWindow: () -> Void = {}

    private init() {}
}
