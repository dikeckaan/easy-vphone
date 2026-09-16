import SwiftUI
import AppKit

struct StoreApp: Identifiable, Decodable {
    let id: Int
    let bundleID: String
    let name: String
    let version: String
    let price: Double
}
struct SearchEnvelope: Decodable { let apps: [StoreApp] }
struct CommandResult { let code: Int32; let output: String }
func runTool(_ args: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ipatool")
    process.arguments = args + ["--format", "json", "--non-interactive"]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    process.environment = env
    let pipe = Pipe()
    process.standardOutput = pipe; process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch { return CommandResult(code: -1, output: error.localizedDescription) }
}
func toolError(_ result: CommandResult) -> String {
    for line in result.output.split(separator: "\n").reversed() {
        if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
           let error = object["error"] as? String { return error }
    }
    return result.output.isEmpty ? localizedMessage("job.failed", result.code) : String(result.output.suffix(1400))
}

@MainActor final class BrowserModel: ObservableObject {
    @Published var query = ""
    @Published var apps: [StoreApp] = []
    @Published var selected: Int?
    @Published var files: [URL] = []
    @Published var busy = false
    @Published var checking = false
    @Published var loggedIn = false
    @Published var hasSearched = false
    @Published var status = tr("ipa.prompt")
    @Published var error: String?
    @Published var folder: URL
    @Published var tab = 0
    init() {
        folder = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "downloadFolder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("easy-vphone/apps").path)
        refreshFiles()
    }
    var current: StoreApp? { apps.first { $0.id == selected } }
    func checkSession() {
        guard !checking, !busy else { return }
        checking = true
        Task {
            let result = await Task.detached { runTool(["auth", "info"]) }.value
            loggedIn = result.code == 0
            checking = false
        }
    }
    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !busy else { return }
        busy = true; error = nil; status = tr("ipa.searching"); tab = 0
        Task {
            let result = await Task.detached { runTool(["search", term, "--limit", "25", "--platform", "iphone"]) }.value
            busy = false; hasSearched = true
            guard result.code == 0 else { error = toolError(result); status = tr("ipa.search_failed"); return }
            let envelopes = result.output.split(separator: "\n").compactMap { try? JSONDecoder().decode(SearchEnvelope.self, from: Data($0.utf8)) }
            guard let envelope = envelopes.last else { error = tr("ipa.response_failed"); return }
            apps = envelope.apps; selected = apps.first?.id
            status = localizedMessage("ipa.found", apps.count)
        }
    }
    func download(_ app: StoreApp) {
        guard !busy else { return }
        // Refuse to recreate a missing removable volume under /Volumes.
        if folder.path.hasPrefix("/Volumes/") {
            let components = folder.pathComponents
            guard components.count > 2,
                  (try? URL(fileURLWithPath: "/Volumes/" + components[2]).resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == true,
                  FileManager.default.fileExists(atPath: "/Volumes/" + components[2]) else {
                error = tr("ipa.drive_missing"); return
            }
        }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription; return }
        let safe = app.bundleID.filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }
        let base = "\(safe)-\(app.id)-\(app.version.filter { $0.isLetter || $0.isNumber || ".-_".contains($0) })"
        let destination = folder.appendingPathComponent(base + ".ipa")
        if FileManager.default.fileExists(atPath: destination.path) {
            status = tr("ipa.exists"); refreshFiles(); tab = 1
            NSWorkspace.shared.activateFileViewerSelecting([destination]); return
        }
        let partial = folder.appendingPathComponent(base + "-" + UUID().uuidString + ".partial.ipa")
        var args = ["download", "--app-id", String(app.id), "--platform", "iphone", "--output", partial.path]
        if app.price == 0 { args.append("--purchase") }
        busy = true; error = nil; status = localizedMessage("ipa.downloading", app.name)
        Task {
            let command = args
            let result = await Task.detached { runTool(command) }.value
            busy = false
            guard result.code == 0 else {
                error = toolError(result); status = tr("ipa.download_failed")
                if let error, error.localizedCaseInsensitiveContains("auth") || error.localizedCaseInsensitiveContains("account") || error.localizedCaseInsensitiveContains("session") { loggedIn = false }
                try? FileManager.default.removeItem(at: partial)
                return
            }
            do {
                try FileManager.default.moveItem(at: partial, to: destination)
                refreshFiles(); tab = 1; status = localizedMessage("ipa.downloaded", app.name)
            } catch { self.error = error.localizedDescription }
        }
    }
    func refreshFiles() {
        files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "ipa" && !$0.lastPathComponent.contains(".partial.") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.prompt = tr("ipa.folder_prompt")
        if panel.runModal() == .OK, let url = panel.url {
            folder = url; UserDefaults.standard.set(url.path, forKey: "downloadFolder"); refreshFiles()
        }
    }
}

struct BrowserView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: BrowserModel
    @ObservedObject var vm: VMModel
    @ObservedObject var console: ConsoleModel
    @Environment(\.scenePhase) var scenePhase
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square.fill").font(.system(size: 30)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("nav.ipa")).font(.title2.bold())
                    Text(tr("ipa.subtitle")).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(model.loggedIn ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(model.checking ? tr("ipa.session_check") : model.loggedIn ? tr("ipa.session_ready") : tr("ipa.login_needed")).font(.callout)
                if !model.loggedIn { Button(tr("ipa.login")) {
                    console.completion = { model.checkSession() }
                    console.start(title:tr("ipa.login_title"), executable:"/opt/homebrew/bin/ipatool", args:["auth","login"], sensitive:true)
                }.disabled(model.busy || model.checking) }
                Button { model.checkSession(); model.refreshFiles() } label: { Image(systemName: "arrow.clockwise") }.help(tr("ipa.refresh")).disabled(model.busy)
            }.padding(24)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("ipa.search_placeholder"), text: $model.query)
                    .textFieldStyle(.plain).onSubmit(model.search)
                Button(tr("ipa.search"), action: model.search).buttonStyle(.borderedProminent).tint(.indigo)
                    .disabled(model.busy || model.query.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal,24)
            Picker(tr("ipa.view"), selection: $model.tab) {
                Text(tr("ipa.results")).tag(0); Text(tr("ipa.download_count", model.files.count)).tag(1)
            }.pickerStyle(.segmented).frame(width: 330).padding(20)
            HStack {
                Picker(tr("ipa.target"),selection:$vm.selected) {
                    Text(tr("ipa.choose_vm")).tag(Optional<String>.none)
                    ForEach(vm.vms) { item in Text(item.name + (item.running ? tr("vm.on_suffix") : tr("vm.off_suffix"))).tag(Optional(item.name)) }
                }.frame(maxWidth:420)
                Spacer()
                Button(tr("ipa.local"),action:vm.chooseIPA).disabled(vm.current?.running != true || console.running)
            }.padding(.horizontal,24).padding(.bottom,12)
            if !vm.message.isEmpty { Text(tr(vm.message)).font(.caption).foregroundStyle(.orange).padding(.horizontal,24) }
            Divider()
            if model.tab == 0 {
                HSplitView {
                    if model.apps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: model.hasSearched ? "magnifyingglass" : "square.stack.3d.up").font(.system(size:40)).foregroundStyle(.tertiary)
                            Text(model.hasSearched ? tr("ipa.no_results") : tr("ipa.discover")).font(.headline)
                            Text(model.hasSearched ? tr("ipa.try_again") : tr("ipa.results_help")).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.apps, selection: $model.selected) { app in
                            HStack(spacing: 12) {
                                Text(String(app.name.prefix(1))).font(.title2.bold()).foregroundStyle(.indigo).frame(width:42,height:42).background(.indigo.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
                                VStack(alignment:.leading,spacing:4) {
                                    Text(app.name).font(.headline)
                                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(app.price == 0 ? tr("ipa.free") : tr("ipa.paid")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical,7).tag(app.id)
                        }.listStyle(.inset).frame(minWidth: 390)
                    }
                    VStack(alignment:.leading,spacing:18) {
                        if let app = model.current {
                            Image(systemName:"app.badge").font(.system(size:42)).foregroundStyle(.indigo)
                            Text(app.name).font(.title2.bold())
                            Text(app.bundleID).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            LabeledContent(tr("ipa.version"), value: app.version)
                            LabeledContent(tr("ipa.platform"), value:"iPhone")
                            Button { model.download(app) } label: { Label(tr("ipa.download"), systemImage:"arrow.down.circle.fill").frame(maxWidth:.infinity) }
                                .controlSize(.large).buttonStyle(.borderedProminent).tint(.indigo).disabled(model.busy || !model.loggedIn)
                            Link(tr("ipa.store_link"),destination:URL(string:"https://apps.apple.com/app/id\(app.id)")!)
                            if app.price != 0 { Text(tr("ipa.paid_help")).font(.caption).foregroundStyle(.secondary) }
                            Text(tr("ipa.fairplay")).font(.caption).foregroundStyle(.secondary)
                        } else { Text(tr("ipa.select_help")).foregroundStyle(.secondary) }
                        Spacer()
                    }.padding(24).frame(minWidth:280,idealWidth:310,maxWidth:350)
                }
            } else {
                if model.files.isEmpty {
                    VStack(spacing:12) { Image(systemName:"tray").font(.largeTitle); Text(tr("ipa.empty")); Text(tr("ipa.empty_help")).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    List(model.files,id:\.path) { file in
                        HStack {
                            Image(systemName:"doc.zipper").font(.title2).foregroundStyle(.indigo)
                            VStack(alignment:.leading,spacing:4) {
                                Text(file.lastPathComponent).font(.headline)
                                Text(ByteCountFormatter.string(fromByteCount:Int64((try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0),countStyle:.file)).foregroundStyle(.secondary).font(.caption)
                            }; Spacer()
                            Button(tr("ipa.install_selected")) { vm.installIPA(file) }.disabled(vm.current?.running != true || console.running)
                            Button(tr("ipa.finder")) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                        }.padding(.vertical,8)
                    }
                }
            }
            Divider()
            VStack(alignment:.leading,spacing:10) {
                if let error = model.error { Text(tr(error)).font(.callout).foregroundStyle(.red).textSelection(.enabled).lineLimit(4) }
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(tr(model.status)).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("common.choose_folder"),action:model.chooseFolder).disabled(model.busy)
                }
                Text(model.folder.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }.padding(18)
        }.frame(minWidth:850,minHeight:600)
            .onAppear { model.refreshFiles(); model.checkSession() }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in model.checkSession(); model.refreshFiles() }
    }
}
