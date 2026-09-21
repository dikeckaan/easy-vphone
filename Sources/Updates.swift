import SwiftUI
import AppKit

@MainActor final class UpdateModel: ObservableObject {
    @Published var available: AppRelease?
    @Published var checking = false
    @Published var status = ""
    private var lastCheck: Date?
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    func check(force: Bool = false) {
        guard !checking, force || lastCheck.map({Date().timeIntervalSince($0) > 21600}) ?? true else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url:URL(string:"https://api.github.com/repos/dikeckaan/easy-vphone/releases?per_page=100")!)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
                let (data, response) = try await URLSession.shared.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let releases = try JSONDecoder().decode([AppRelease].self,from:data)
                available = AppRelease.newest(in:releases,current:current); lastCheck = Date()
                status = tr("update.current")
            } catch { status = tr("update.failed"); lastCheck = Date() }
        }
    }
}

struct UpdateBanner: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: UpdateModel
    var body: some View {
        if let release = model.available, let url = release.downloadURL {
            HStack {
                Image(systemName:"arrow.down.circle.fill").foregroundStyle(appAccent)
                Text(tr("update.available",release.tag_name))
                Spacer()
                Link(tr("update.download"),destination:url)
                Button(tr("update.brew")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew update && brew upgrade --cask dikeckaan/easy-vphone/easy-vphone",forType:.string)
                }
            }.padding(12).background(appAccent.opacity(0.12))
        }
    }
}
