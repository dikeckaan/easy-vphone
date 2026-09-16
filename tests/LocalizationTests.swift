import Foundation

@main struct LocalizationTests {
    static func main() throws {
        let directory = URL(fileURLWithPath:CommandLine.arguments[1])
        var catalogs: [String:[String:String]] = [:]
        for lang in Localizer.supported {
            catalogs[lang] = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:directory.appendingPathComponent(lang + ".json")))
        }
        precondition(Localizer.resolve("system",preferred:["fr-CA"]) == "fr")
        precondition(Localizer.resolve("system",preferred:["zh-Hant-TW"]) == "zh-Hans")
        precondition(Localizer.resolve("system",preferred:["unsupported"]) == "en")
        precondition(Localizer.resolve("tr",preferred:["en-US"]) == "tr")
        precondition(Localizer.render("ipa.download_count",arguments:["12"],language:"de",catalogs:catalogs) == "Downloads (12)")
        precondition(Localizer.render("ipa.download_count",arguments:["12"],language:"ja",catalogs:catalogs) == "ダウンロード (12)")
        precondition(Localizer.render("nav.vms",arguments:[],language:"absent",catalogs:catalogs) == "Virtual machines")
        precondition(Localizer.render("external tool output",arguments:[],language:"fr",catalogs:catalogs) == "external tool output")
        let special = Localizer.render("job.vm_exit",arguments:["{1}","log"],language:"en",catalogs:catalogs)
        precondition(special == "VM exit code {1}. log", "Arguments must not recursively expand placeholders")
        let encoded = localizedMessage("job.starting","VM {0} 日本語")
        let decoded = try JSONDecoder().decode(LocalizedMessage.self,from:Data(encoded.dropFirst().utf8))
        precondition(decoded.arguments == ["VM {0} 日本語"])
        precondition(Localizer.render(decoded.key,arguments:decoded.arguments,language:"en",catalogs:catalogs) == "Starting VM {0} 日本語…")
        print("Localization runtime: 10 checks passed")
    }
}
