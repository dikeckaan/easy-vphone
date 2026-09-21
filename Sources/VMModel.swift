import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FirmwareCatalog: Decodable {
    struct Firmware: Decodable { let name: String; let url: String }
    struct Entry: Decodable, Identifiable {
        var id: String { ios.url }
        let ios: Firmware
        let recommendedCloudOS: Firmware
    }
    let pairings: [Entry]
}
struct VMItem: Identifiable {
    var id: String { name }
    let name: String
    let directory: URL
    let cpu: Int
    let memoryGB: Int
    let diskGB: Int
    let version: String
    let variant: String
    let running: Bool
}
struct HostCheck: Identifiable {
    let id: String
    let good: Bool
    let detail: String
}

@MainActor final class VMModel: ObservableObject {
    @Published var root: String { didSet { UserDefaults.standard.set(root,forKey:"vmRoot") } }
    @Published var selected: String?
    @Published var vms: [VMItem] = []
    @Published var scanning = false
    @Published var checks: [HostCheck] = []
    @Published var checking = false
    @Published var message = ""
    @Published var name = "iphone-vm"
    @Published var variant = "jb"
    @Published var profile = "ios27"
    @Published var catalog: [FirmwareCatalog.Entry] = []
    @Published var diskGB = 64
    @Published var frida = false
    @Published var iphoneSource = ""
    @Published var cloudSource = ""
    @Published var xcodeDir: String { didSet { UserDefaults.standard.set(xcodeDir,forKey:"xcodeDir") } }
    @Published var resolvingTarget = false
    @Published var sshPort = "22222"
    @Published var sshUser = "mobile"
    @Published var configCPU = 8
    @Published var configRAM = 8
    private var launches: [String:Process] = [:]
    let console: ConsoleModel
    static let ios27 = "https://updates.cdn-apple.com/2026FallFCS/5130b3f9-3b4e-469a-b60e-93f6b310cdd9/iPhone17,3_27.0_24A437_Restore.ipsw"
    static let cloud26 = "https://updates.cdn-apple.com/private-cloud-compute/c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ada27273262b0b8b64"
    init(console: ConsoleModel) {
        self.console = console
        let args = CommandLine.arguments
        if let i = args.firstIndex(of:"--root"), args.indices.contains(i+1) { root = args[i+1] }
        else { root = UserDefaults.standard.string(forKey:"vmRoot") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("easy-vphone").path }
        xcodeDir = UserDefaults.standard.string(forKey:"xcodeDir") ?? ""
    }
    var current: VMItem? { vms.first { $0.name == selected } }
    var environment: [String:String] {
        ["VPHONE_ROOT":root,"VPHONE_LIBRARY_ROOT":root + "/VMs","VPHONE_VENV_DIR":root + "/venv"]
    }
    var validName: Bool { name.range(of:"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$",options:.regularExpression) != nil }
    var validRoot: Bool { root.hasPrefix("/") && root != "/" }
    var canCreate: Bool {
        validName && validRoot && !console.running && !FileManager.default.fileExists(atPath:root + "/VMs/" + name)
        && (profile != "custom" || (validSource(iphoneSource) && validSource(cloudSource)))
    }
    func validSource(_ text: String) -> Bool {
        if text.hasPrefix("/") { return FileManager.default.fileExists(atPath:text) }
        return URL(string:text)?.scheme == "https"
    }
    func chooseRoot() {
        guard !console.running else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = tr("storage.instructions")
        panel.prompt = tr("storage.prompt")
        if panel.runModal() == .OK, let url = panel.url {
            root = url.lastPathComponent == "VMs" ? url.deletingLastPathComponent().path : url.path
            selected = nil; refresh()
        }
    }
    func chooseXcode() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowedContentTypes = [.applicationBundle]
        panel.message = tr("setup.xcode_prompt")
        if panel.runModal() == .OK, let url = panel.url { xcodeDir = url.appendingPathComponent("Contents/Developer").path; checkHost() }
    }
    func pickSource(iphone: Bool) {
        let p = NSOpenPanel(); p.canChooseDirectories = false
        if p.runModal() == .OK, let url = p.url { if iphone { iphoneSource = url.path } else { cloudSource = url.path } }
    }
    func refresh() {
        guard !scanning else { return }; scanning = true
        let base = root
        Task {
            let list: [VMItem] = await Task.detached {
                let fm = FileManager.default
                let directories = (try? fm.contentsOfDirectory(at:URL(fileURLWithPath:base).appendingPathComponent("VMs"),includingPropertiesForKeys:nil)) ?? []
                return directories.compactMap { dir -> VMItem? in
                    guard let data = try? Data(contentsOf:dir.appendingPathComponent("config.plist")),
                          let plist = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { return nil }
                    let restoreData = try? Data(contentsOf:dir.appendingPathComponent("restore-info.json"))
                    let info = restoreData.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
                    let planData = try? Data(contentsOf:URL(fileURLWithPath:base).appendingPathComponent("easy-runtime/" + dir.lastPathComponent + "/plan.json"))
                    let plan = planData.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:String] }
                    let disk = dir.appendingPathComponent(plist["diskImage"] as? String ?? "Disk.img")
                    let bytes = (try? fm.attributesOfItem(atPath:disk.path)[.size] as? NSNumber)?.int64Value ?? 0
                    let alive = capture("/usr/sbin/lsof",["-t","--",disk.path]).code == 0
                    return VMItem(name:dir.lastPathComponent,directory:dir,cpu:plist["cpuCount"] as? Int ?? 8,
                        memoryGB:(plist["memorySize"] as? Int ?? 0)/1073741824,diskGB:Int(bytes/1073741824),
                        version:(info?["ios"] as? [String:Any])?["version"] as? String ?? tr("check.incomplete"),
                        variant:info?["variant"] as? String ?? plan?["VARIANT"] ?? "?",running:alive)
                }.sorted { $0.name < $1.name }
            }.value
            if base == root { vms = list; if !list.contains(where:{$0.name == selected}) { selected = list.first?.name } }
            scanning = false
        }
    }
    func loadCatalog() {
        Task {
            let result = await Task.detached { capture(vphoneCLI,["fw","catalog","--json"]) }.value
            if result.code == 0, let decoded = try? JSONDecoder().decode(FirmwareCatalog.self,from:Data(result.output.utf8)) { catalog = decoded.pairings.reversed() }
        }
    }
    var chosenPair: FirmwareCatalog.Entry? { catalog.first { $0.id == profile } }
    var profileTitle: String { profile == "ios27" ? "iPhone17,3 · iOS 27.0 (24A437)" : chosenPair?.ios.name ?? tr("create.custom_short") }
    func checkHost() {
        guard !checking else { return }; checking = true
        let xcode = xcodeDir
        Task {
            let result = await Task.detached { () -> [HostCheck] in
                let fm = FileManager.default
                let arch = capture("/usr/bin/uname",["-m"]).output.trimmingCharacters(in:.whitespacesAndNewlines)
                let sip = capture("/usr/bin/csrutil",["status"])
                let research = capture("/usr/bin/csrutil",["allow-research-guests","status"])
                let cli = fm.isExecutableFile(atPath:vphoneCLI) ? capture(vphoneCLI,["--help"]) : CommandResult(code:-1,output:tr("check.absent"))
                var sdk = capture("/usr/bin/xcrun",["--sdk","iphoneos","--show-sdk-path"],env:xcode.isEmpty ? [:] : ["DEVELOPER_DIR":xcode])
                if sdk.code != 0 && xcode.isEmpty {
                    let apps = ((try? fm.contentsOfDirectory(atPath:"/Applications")) ?? []).filter{$0.hasPrefix("Xcode") && $0.hasSuffix(".app")}
                    for app in apps {
                        sdk = capture("/usr/bin/xcrun",["--sdk","iphoneos","--show-sdk-path"],env:["DEVELOPER_DIR":"/Applications/\(app)/Contents/Developer"])
                        if sdk.code == 0 { break }
                    }
                }
                return [
                    HostCheck(id:"Apple Silicon",good:arch == "arm64",detail:arch),
                    HostCheck(id:"Homebrew",good:fm.isExecutableFile(atPath:"/opt/homebrew/bin/brew"),detail:tr("check.brew")),
                    HostCheck(id:"Xcode / iOS SDK",good:sdk.code == 0,detail:sdk.code == 0 ? sdk.output.trimmingCharacters(in:.whitespacesAndNewlines) : tr("check.sdk")),
                    HostCheck(id:"SIP",good:sip.output.lowercased().contains("disabled") || sip.output.lowercased().contains("debugging restrictions: disabled"),detail:sip.output.trimmingCharacters(in:.whitespacesAndNewlines)),
                    HostCheck(id:tr("check.research"),good:research.code == 0 && research.output.lowercased().contains("enabled"),detail:research.code == 0 ? research.output.trimmingCharacters(in:.whitespacesAndNewlines) : tr("check.research_unknown")),
                    HostCheck(id:"vphone-cli / AMFI",good:cli.code == 0,detail:cli.code == 0 ? tr("check.cli_ok") : tr("check.cli_bad")),
                    HostCheck(id:tr("nav.ipa"),good:fm.isExecutableFile(atPath:"/opt/homebrew/bin/ipatool"),detail:tr("check.session"))]
            }.value
            checks = result; checking = false; loadCatalog()
        }
    }
    func install(_ action: String) {
        guard !console.running,validRoot else { return }
        if action == "create" && !canCreate { return }
        guard let script = Bundle.main.path(forResource:"install",ofType:"sh") else { return }
        let vm = action == "cfw" ? (selected ?? name) : name
        var env = environment
        env.merge(["ROOT":root,"VM_NAME":vm,"VARIANT": action == "cfw" ? (current?.variant == "?" ? variant : current?.variant ?? variant) : variant,
                   "DISK_GB":String(diskGB),"XCODE_DIR":xcodeDir,"FRIDA":frida && ["jb","exp"].contains(variant) ? "1" : "0"]) { _, n in n }
        env["IPHONE_SOURCE"] = profile == "ios27" ? Self.ios27 : chosenPair?.ios.url ?? iphoneSource
        env["CLOUDOS_SOURCE"] = profile == "ios27" ? Self.cloud26 : chosenPair?.recommendedCloudOS.url ?? cloudSource
        console.completion = { [weak self] in self?.refresh(); self?.checkHost() }
        console.start(title:["create":localizedMessage("job.install", vm),"cfw":localizedMessage("job.resume", vm),"dependencies":tr("job.dependencies"),"amfi":tr("job.amfi")][action] ?? action,
                      executable:"/bin/bash",args:[script,action],env:env)
    }
    func launch() {
        guard let vm = current,!vm.running,!console.running else { return }
        let key = vm.directory.path
        guard launches[key] == nil else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath:vphoneCLI)
        var args = ["vm","launch",vm.name]
        let runtime = root + "/easy-runtime/" + vm.name
        if FileManager.default.fileExists(atPath:runtime) { args += ["--project-root",runtime] }
        p.arguments = args; p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, n in n }.merging(["PATH":toolPATH]) { _,n in n }
        p.standardInput = FileHandle.nullDevice
        // A regular file survives the manager closing; a pipe can SIGPIPE the VM
        // when its last reader disappears. Keep diagnostics in local caches.
        let logDirectory = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("io.github.easy-vphone/VMLogs",isDirectory:true)
        let logURL = logDirectory.appendingPathComponent(UUID().uuidString + ".log")
        let log: FileHandle
        do {
            try FileManager.default.createDirectory(at:logDirectory,withIntermediateDirectories:true)
            guard FileManager.default.createFile(atPath:logURL.path,contents:nil) else { throw CocoaError(.fileWriteUnknown) }
            log = try FileHandle(forWritingTo:logURL)
        } catch { message = error.localizedDescription; return }
        p.standardOutput = log; p.standardError = log
        launches[key] = p; message = localizedMessage("job.starting", vm.name)
        do { try p.run() } catch { launches[key] = nil; try? log.close(); message = error.localizedDescription; return }
        DispatchQueue.global(qos:.utility).async { [weak self] in
            p.waitUntilExit()
            try? log.close()
            var tail = ""
            if let input = try? FileHandle(forReadingFrom:logURL) {
                if let length = try? input.seekToEnd() {
                    try? input.seek(toOffset:length > 1800 ? length - 1800 : 0)
                    tail = String(decoding:(try? input.readToEnd()) ?? Data(),as:UTF8.self)
                }
                try? input.close()
            }
            let diagnostics = tail
            DispatchQueue.main.async {
                guard let self else { return }
                self.launches[key] = nil
                self.message = p.terminationStatus == 0 ? localizedMessage("job.stopped", vm.name) : localizedMessage("job.vm_exit", p.terminationStatus, diagnostics)
                self.refresh()
            }
        }
        refresh()
    }
    func showWindow() {
        guard let vm = current, vm.running else { return }
        Task {
            let result = await Task.detached { capture("/usr/sbin/lsof",["-t","--",vm.directory.appendingPathComponent("Disk.img").path]) }.value
            for line in result.output.split(separator:"\n") {
                if let pid = Int32(line), let app = NSRunningApplication(processIdentifier:pid) { app.activate(options:[]) }
            }
        }
    }
    func chooseIPA() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension:"ipa") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { installIPA(url) }
    }
    func stop() {
        guard let vm = current,vm.running,!console.running else { return }
        console.completion = { [weak self] in self?.refresh() }
        console.start(title:localizedMessage("job.stop", vm.name),executable:vphoneCLI,args:["vm","stop",vm.name,"--timeout","30"],env:environment)
    }
    private var sshKey: String { "ssh:" + root + "/" + (selected ?? "") }
    func loadSSH() {
        let settings = UserDefaults.standard.dictionary(forKey:sshKey) as? [String:String] ?? [:]
        // SSH is routed through usbmux using the selected VM UDID.
        sshPort = settings["port"] ?? "22222"; sshUser = settings["user"] ?? "mobile"
        if let vm = current { configCPU = vm.cpu; configRAM = vm.memoryGB }
    }
    func saveSSH() { UserDefaults.standard.set(["port":sshPort,"user":sshUser],forKey:sshKey) }
    var validSSH: Bool {
        !resolvingTarget && sshUser.range(of:"^[a-zA-Z0-9_][a-zA-Z0-9_-]*$",options:.regularExpression) != nil
        && (1...65535).contains(Int(sshPort) ?? 0)
    }
    func ssh() { startSSH(repair:false) }
    func repairJBApps() { startSSH(repair:true) }
    private func startSSH(repair: Bool) {
        guard let vm = current, validSSH, vm.running, !console.running,
              !repair || ["jb","exp"].contains(vm.variant) else { return }
        guard FileManager.default.isExecutableFile(atPath:"/opt/homebrew/bin/iproxy"),
              let script = Bundle.main.path(forResource:"ssh-vm",ofType:"py") else {
            message = tr("ssh.proxy_missing"); return
        }
        saveSSH(); resolvingTarget = true
        let env = environment; let user = sshUser; let port = sshPort
        Task {
            defer { resolvingTarget = false }
            let result = await Task.detached { capture(vphoneCLI,["vm","info",vm.name,"--json"],env:env) }.value
            guard result.code == 0,
                  let object = try? JSONSerialization.jsonObject(with:Data(result.output.utf8)) as? [String:Any],
                  let udid = object["udid"] as? String,
                  udid.range(of:"^[A-Fa-f0-9-]{16,64}$",options:.regularExpression) != nil else {
                message = tr("ipa.udid_error"); return
            }
            guard current?.directory == vm.directory, !console.running else { return }
            var args = [script,"--udid",udid,"--user",user,"--port",port]
            if repair { args.append("--repair") }
            console.start(title:repair ? tr("repair.title") : "SSH · " + vm.name,
                          executable:pythonPath(),args:args,sensitive:true)
        }
    }
    func configure() {
        guard let vm = current,!vm.running,!console.running else { return }
        console.completion = { [weak self] in self?.refresh() }
        console.start(title:tr("vm.resources_title"),executable:vphoneCLI,args:["vm","config",vm.name,"--cpu",String(configCPU),"--memory",String(configRAM * 1024)],env:environment)
    }
    func installIPA(_ file: URL) {
        guard let vm = current,vm.running,!console.running else { message = tr("ipa.need_running"); return }
        let env = environment
        Task {
            let result = await Task.detached { capture(vphoneCLI,["vm","info",vm.name,"--json"],env:env) }.value
            guard result.code == 0, let object = try? JSONSerialization.jsonObject(with:Data(result.output.utf8)) as? [String:Any],
                  let udid = object["udid"] as? String, !udid.isEmpty else { message = tr("ipa.udid_error"); return }
            guard FileManager.default.isExecutableFile(atPath:"/opt/homebrew/bin/ideviceinstaller") else { message = tr("ipa.installer_missing"); return }
            console.start(title:localizedMessage("job.ipa", vm.name),executable:"/opt/homebrew/bin/ideviceinstaller",args:["-u",udid,"install",file.path])
        }
    }
}
