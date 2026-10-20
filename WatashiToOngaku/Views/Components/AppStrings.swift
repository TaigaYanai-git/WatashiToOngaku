import Foundation

/// Returns the Japanese or English string based on the stored language setting.
/// Use for any string that is NOT a SwiftUI Text literal (e.g. String variables,
/// format strings, programmatic strings, String-typed parameters).
func S(_ ja: String, _ en: String) -> String {
    ThemeStore.shared.language == "en" ? en : ja
}
