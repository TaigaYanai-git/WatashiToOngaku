import Foundation

/// Returns the Japanese, English or Korean string based on the stored language setting.
/// Use for any string that is NOT a SwiftUI Text literal (e.g. String variables,
/// format strings, programmatic strings, String-typed parameters).
/// Korean comes from `koreanStrings` (keyed by the Japanese text); pass `ko` for strings with
/// interpolated values, since they can't be looked up.
func S(_ ja: String, _ en: String, _ ko: String? = nil) -> String {
    switch ThemeStore.shared.language {
    case "en": return en
    case "ko": return ko ?? koreanStrings[ja] ?? en
    default: return ja
    }
}
