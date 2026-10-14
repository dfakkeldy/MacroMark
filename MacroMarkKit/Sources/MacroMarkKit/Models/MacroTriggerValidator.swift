import Foundation

public enum MacroTriggerValidator {
    public static func cleanedTrigger(_ trigger: String) -> String {
        trigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func comparisonKey(for trigger: String, locale: Locale = .current) -> String {
        cleanedTrigger(trigger).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        )
    }

    public static func hasDuplicate(
        _ trigger: String,
        in macros: [Macro],
        excluding excludedMacro: Macro? = nil
    ) -> Bool {
        let key = comparisonKey(for: trigger)
        guard !key.isEmpty else { return false }

        return macros.contains { macro in
            if let excludedMacro, macro === excludedMacro {
                return false
            }
            return comparisonKey(for: macro.trigger) == key
        }
    }
}
