import SwiftUI
import AppKit

final class InterfacePreferences: ObservableObject {
    @Published var language: String { didSet { UserDefaults.standard.set(language,forKey:"interfaceLanguage") } }
    @Published var theme: String { didSet { UserDefaults.standard.set(theme,forKey:"interfaceTheme") } }
    init() {
        let selected = UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "system"
        language = (["system"] + Localizer.supported).contains(selected) ? selected : "system"
        let appearance = UserDefaults.standard.string(forKey:"interfaceTheme") ?? "system"
        theme = ["system","light","dark"].contains(appearance) ? appearance : "system"
    }
    var locale: Locale { Locale(identifier:Localizer.resolve(language)) }
    var scheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
    static let languages: [(String,String)] = [
        ("tr","Türkçe"),("en","English"),("de","Deutsch"),("fr","Français"),("es","Español"),
        ("it","Italiano"),("pt","Português"),("ru","Русский"),("ja","日本語"),("zh-Hans","简体中文")]
}

let appAccent = Color(nsColor:NSColor(name:nil) { appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(calibratedRed:0.25,green:0.86,blue:0.73,alpha:1)
        : NSColor(calibratedRed:0.0,green:0.40,blue:0.33,alpha:1)
})
let panelColor = Color(nsColor:NSColor(name:nil) { appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(calibratedWhite:0.16,alpha:1) : NSColor.white
})

struct PreferencesView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageTitle(title:tr("settings.title"),subtitle:tr("settings.subtitle"))
                Panel {
                    Label(tr("settings.language"),systemImage:"globe").font(.headline)
                    Picker(tr("settings.language"),selection:$preferences.language) {
                        Text(tr("settings.system")).tag("system")
                        ForEach(InterfacePreferences.languages,id:\.0) { code, name in Text(name).tag(code) }
                    }.pickerStyle(.menu)
                    Text(tr("settings.logs")).font(.callout).foregroundStyle(.secondary)
                }
                Panel {
                    Label(tr("settings.theme"),systemImage:"circle.lefthalf.filled").font(.headline)
                    Picker(tr("settings.theme"),selection:$preferences.theme) {
                        Label(tr("settings.system"),systemImage:"desktopcomputer").tag("system")
                        Label(tr("settings.light"),systemImage:"sun.max").tag("light")
                        Label(tr("settings.dark"),systemImage:"moon").tag("dark")
                    }.pickerStyle(.segmented)
                    HStack(spacing:16) {
                        Image(systemName:"iphone.gen3").font(.system(size:44)).foregroundStyle(appAccent)
                        VStack(alignment:.leading,spacing:6) {
                            Text("easy-vphone").font(.title3.bold())
                            Text(tr("app.subtitle")).foregroundStyle(.secondary)
                            Label(tr("vm.running"),systemImage:"circle.fill").font(.caption).foregroundStyle(appAccent)
                        }
                    }.padding(.top,12)
                }
            }.padding(30)
        }
    }
}
