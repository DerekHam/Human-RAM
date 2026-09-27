import Foundation

public enum AppVariant {
    #if HRAM_SHAREABLE
    public static let isShareable = true
    public static let storageFolderName = "HumanRAM Shared"
    #else
    public static let isShareable = false
    public static let storageFolderName = "HumanRAM"
    #endif

    public static var showsGuideByDefault: Bool { isShareable }
}
