import Foundation

/// Extension for convenient localization syntax
/// Usage: "key".localized or "key".localized(with: arg1, arg2)
extension String {
    /// Returns the localized string for this key
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// Returns the localized string formatted with the given arguments
    /// - Parameter args: Arguments to format into the string
    /// - Returns: Formatted localized string
    func localized(with args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
    
    /// Returns the localized string with a specific comment for translators
    /// - Parameter comment: Context for translators
    /// - Returns: Localized string
    func localized(comment: String) -> String {
        NSLocalizedString(self, comment: comment)
    }
}
