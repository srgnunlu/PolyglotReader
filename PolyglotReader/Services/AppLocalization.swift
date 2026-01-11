import Foundation

enum AppLocalization {
    nonisolated static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }
}
