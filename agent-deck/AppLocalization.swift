import Foundation

enum AppLocalization {
    static func string(_ key: String, default defaultValue: String) -> String {
        string(key, default: defaultValue, language: AppSettingsStore.shared.settings.appLanguage)
    }

    static func string(_ key: String, default defaultValue: String, language: AppLanguage) -> String {
        switch language {
        case .system:
            return NSLocalizedString(key, tableName: nil, bundle: .main, value: defaultValue, comment: "")
        case .english:
            return defaultValue
        case .simplifiedChinese:
            guard let bundle = bundle(for: language) else { return defaultValue }
            return NSLocalizedString(key, tableName: nil, bundle: bundle, value: defaultValue, comment: "")
        }
    }

    static func format(_ key: String, default defaultValue: String, _ arguments: CVarArg...) -> String {
        let language = AppSettingsStore.shared.settings.appLanguage
        return String(
            format: string(key, default: defaultValue, language: language),
            locale: language.locale,
            arguments: arguments
        )
    }

    static func thinkingStatus(level: String) -> String {
        format("thinking.status.format", default: "Thinking: %@", thinkingLevel(level))
    }

    static func thinkingLevel(_ level: String) -> String {
        switch level.lowercased() {
        case "off", "none": return string("thinking.level.off", default: "Off")
        case "minimal": return string("thinking.level.minimal", default: "Minimal")
        case "low": return string("thinking.level.low", default: "Low")
        case "medium": return string("thinking.level.medium", default: "Medium")
        case "high": return string("thinking.level.high", default: "High")
        case "xhigh": return string("thinking.level.xhigh", default: "Xhigh")
        case "loading": return string("thinking.loading", default: "Loading")
        default: return level.capitalized
        }
    }

    static func modelImageSupportLabel(_ supportsImages: Bool) -> String {
        supportsImages
            ? string("Images", default: "Images")
            : string("Text Only", default: "Text Only")
    }

    static func modelThinkingSupportLabel(_ supportsThinking: Bool) -> String {
        supportsThinking
            ? string("Thinking", default: "Thinking")
            : string("No Thinking", default: "No Thinking")
    }

    static func agentDescription(name: String, default defaultValue: String) -> String {
        let trimmed = defaultValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return string("No description", default: "No description") }
        return string("agent.description.\(name)", default: trimmed)
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let localization = language.bundleLocalization,
              let path = Bundle.main.path(forResource: localization, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
