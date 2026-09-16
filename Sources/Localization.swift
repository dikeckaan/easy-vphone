import Foundation

/// Immutable catalogs, shared by the UI and background tasks. Unknown tool output
/// is passed through; application messages use stable keys and numbered arguments.
enum Localizer {
    static let supported = ["tr", "en", "de", "fr", "es", "it", "pt", "ru", "ja", "zh-Hans"]
    static let catalogs: [String:[String:String]] = {
        var result: [String:[String:String]] = [:]
        for language in supported {
            if let url = Bundle.main.url(forResource:language,withExtension:"json",subdirectory:"i18n"),
               let data = try? Data(contentsOf:url),
               let strings = try? JSONDecoder().decode([String:String].self,from:data) { result[language] = strings }
        }
        return result
    }()
    static let reverse: [String:String] = {
        var result: [String:String] = [:]
        for lang in supported {
            for (key,value) in catalogs[lang] ?? [:] where !value.contains("{0}") { result[value] = key }
        }
        return result
    }()
    static func resolve(_ selection: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if supported.contains(selection) { return selection }
        for language in preferred {
            let normalized = language.replacingOccurrences(of:"_",with:"-")
            if normalized.hasPrefix("zh") { return "zh-Hans" }
            if let match = supported.first(where:{normalized == $0 || normalized.hasPrefix($0 + "-")}) { return match }
        }
        return "en"
    }
    static var language: String { resolve(UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "system") }
    static func render(_ key: String, arguments: [String], language: String, catalogs: [String:[String:String]] = catalogs) -> String {
        let template = catalogs[language]?[key] ?? catalogs["en"]?[key] ?? key
        // One pass: placeholder-like text inside an argument is never interpreted.
        let pattern = try! NSRegularExpression(pattern:"\\{([0-9]+)\\}")
        let source = template as NSString
        var output = ""; var cursor = 0
        for match in pattern.matches(in:template,range:NSRange(location:0,length:source.length)) {
            output += source.substring(with:NSRange(location:cursor,length:match.range.location-cursor))
            let index = Int(source.substring(with:match.range(at:1)))!
            output += index < arguments.count ? arguments[index] : source.substring(with:match.range)
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from:cursor)
        return output
    }
}
struct LocalizedMessage: Codable { let key: String; let arguments: [String] }
func localizedMessage(_ key: String, _ arguments: Any...) -> String {
    let value = LocalizedMessage(key:key,arguments:arguments.map { String(describing:$0) })
    let data = try! JSONEncoder().encode(value)
    return "\u{001E}" + String(decoding:data,as:UTF8.self)
}
func tr(_ source: String, _ arguments: Any...) -> String {
    if source.hasPrefix("\u{001E}"), let value = try? JSONDecoder().decode(LocalizedMessage.self,from:Data(source.dropFirst().utf8)) {
        return Localizer.render(value.key,arguments:value.arguments,language:Localizer.language)
    }
    let key = Localizer.catalogs["en"]?[source] != nil ? source : Localizer.reverse[source] ?? source
    return Localizer.render(key,arguments:arguments.map { String(describing:$0) },language:Localizer.language)
}
