import SwiftUI
import AppKit
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var console: ConsoleModel?
    var browser: BrowserModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if console?.running == true || browser?.busy == true {
            let alert = NSAlert(); alert.messageText = tr("console.quit_title")
            alert.informativeText = tr("console.quit_help")
            alert.runModal(); console?.presented = true; return .terminateCancel
        }
        return .terminateNow
    }
}

@main struct EasyVPhoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var console: ConsoleModel
    @StateObject private var model: VMModel
    @StateObject private var browser = BrowserModel()
    @StateObject private var preferences = InterfacePreferences()
    init() {
        let c = ConsoleModel(); _console = StateObject(wrappedValue:c); _model = StateObject(wrappedValue:VMModel(console:c))
    }
    var body: some Scene {
        Window("easy-vphone",id:"main") {
            MainView(model:model,console:console,browser:browser).environmentObject(preferences)
                .environment(\.locale,preferences.locale)
                .preferredColorScheme(preferences.scheme)
                .onAppear { delegate.console = console; delegate.browser = browser }
        }.defaultSize(width:1180,height:790)
        .commands {
            CommandGroup(after:.newItem) {
                Button(tr("vm.refresh"),action:model.refresh).keyboardShortcut("r")
                Button(tr("vm.start_selected"),action:model.launch).keyboardShortcut("b",modifiers:[.command,.shift])
                Button(tr("ssh.open"),action:model.ssh).keyboardShortcut("s",modifiers:[.command,.shift])
            }
        }
    }
}

struct MainView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: VMModel
    @ObservedObject var console: ConsoleModel
    @ObservedObject var browser: BrowserModel
    @StateObject private var updates = UpdateModel()
    @State private var section = "vms"
    private let timer = Timer.publish(every:8,on:.main,in:.common).autoconnect()
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:10) {
                    Image(systemName:"iphone.gen3.radiowaves.left.and.right").font(.system(size:25)).foregroundStyle(appAccent)
                    VStack(alignment:.leading) { Text("easy-vphone").font(.headline); Text(tr("app.subtitle")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical,27)
                nav(tr("nav.vms"),"square.stack.3d.up","vms")
                nav(tr("nav.create"),"plus.circle","create")
                nav(tr("nav.ipa"),"square.and.arrow.down","ipa")
                nav(tr("nav.setup"),"checklist","setup")
                nav(tr("nav.settings"),"gearshape","settings")
                Spacer()
                if console.running { Button { console.presented = true } label: { Label(tr("console.active"),systemImage:"circle.dotted").foregroundStyle(appAccent) }.buttonStyle(.plain).padding(.bottom,12) }
                Button { console.presented = true } label: { Label(tr("console.log"),systemImage:"terminal") }.buttonStyle(.plain).foregroundStyle(.secondary)
                Divider().padding(.vertical,10)
                Text(tr("storage.title")).font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
                Text(model.root).font(.caption).lineLimit(3).textSelection(.enabled).help(model.root)
                Button(tr("storage.import"),action:model.chooseRoot).font(.caption).disabled(console.running)
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") · Apple Silicon").font(.caption2).foregroundStyle(.tertiary).padding(.top,12)
            }.padding(.horizontal,20).padding(.bottom,20).frame(width:230).background(Color(nsColor:.windowBackgroundColor))
            Divider()
            Group {
                switch section {
                case "create": CreateView(model:model)
                case "ipa": BrowserView(model:browser,vm:model,console:console)
                case "setup": SetupView(model:model)
                case "settings": PreferencesView(updates:updates)
                default: MachinesView(model:model)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:1120,minHeight:740)
        .safeAreaInset(edge:.top,spacing:0) { UpdateBanner(model:updates) }
        .sheet(isPresented:$console.presented) { ConsoleView(model:console) }
        .onAppear { updates.check(); browser.useDefaultFolder(root:model.root); model.refresh(); model.checkHost() }
        .onChange(of:model.root) { _, _ in if !browser.busy { browser.useDefaultFolder(root:model.root) } }
        .onReceive(timer) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in updates.check() }
        .onChange(of:model.selected) { _, _ in model.loadSSH() }
    }
    func nav(_ label: String,_ icon: String,_ tag: String) -> some View {
        Button { section = tag } label: {
            Label(label,systemImage:icon).font(.system(size:14,weight:section == tag ? .semibold : .regular))
                .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                .background(section == tag ? appAccent.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:10))
                .foregroundStyle(section == tag ? appAccent : .primary)
        }.buttonStyle(.plain)
    }
}

struct PageTitle: View {
    @EnvironmentObject var preferences: InterfacePreferences
    let title: String; let subtitle: String
    var body: some View { VStack(alignment:.leading,spacing:7) { Text(title).font(.system(size:29,weight:.bold)); Text(subtitle).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading) }
}
struct Panel<Content:View>: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment:.leading,spacing:16) { content }.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(panelColor,in:RoundedRectangle(cornerRadius:16)) }
}

struct MachinesView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: VMModel
    @State private var confirmStop = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack { PageTitle(title:tr("nav.vms"),subtitle:tr("vm.subtitle")); Button(action:model.refresh) { Image(systemName:"arrow.clockwise") }.disabled(model.scanning) }
                if model.vms.isEmpty {
                    Panel {
                        Image(systemName:"iphone.gen3").font(.system(size:42)).foregroundStyle(appAccent)
                        Text(tr("vm.empty")).font(.title2.bold())
                        Text(tr("vm.empty_help")).foregroundStyle(.secondary)
                        Button(tr("vm.import"),action:model.chooseRoot)
                    }
                } else {
                    Picker(tr("vm.machine"),selection:$model.selected) { ForEach(model.vms) { vm in Text(vm.name).tag(Optional(vm.name)) } }.pickerStyle(.menu)
                    if let vm = model.current {
                        Panel {
                            HStack(spacing:18) {
                                Image(systemName:"iphone.gen3").font(.system(size:52)).foregroundStyle(appAccent).frame(width:70,height:80)
                                VStack(alignment:.leading,spacing:7) {
                                    Text(vm.name).font(.title2.bold())
                                    Text("iOS \(tr(vm.version)) · \(vm.variant.uppercased())").foregroundStyle(.secondary)
                                    Label(vm.running ? tr("vm.running") : tr("vm.off"),systemImage:"circle.fill").font(.caption).foregroundStyle(vm.running ? .green : .secondary)
                                }; Spacer()
                                VStack(alignment:.trailing,spacing:8) {
                                    Text("\(vm.cpu) CPU  ·  \(vm.memoryGB) GB RAM").font(.headline)
                                    Text(tr("vm.disk_size", vm.diskGB)).foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                            HStack {
                                Button(action:model.launch) { Label(tr("vm.start"),systemImage:"play.fill") }.buttonStyle(.borderedProminent).tint(appAccent).disabled(vm.running || model.console.running)
                                Button { confirmStop = true } label: { Label(tr("vm.stop"),systemImage:"power") }.disabled(!vm.running || model.console.running)
                                Button(tr("vm.show"),action:model.showWindow).disabled(!vm.running)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([vm.directory]) } label: { Label(tr("common.files"),systemImage:"folder") }
                                Spacer()
                                Button(tr("vm.resume")) { model.install("cfw") }.disabled(vm.running || model.console.running)
                            }.controlSize(.large)
                        }
                        Panel {
                            Label(tr("ssh.title"),systemImage:"terminal").font(.headline)
                            Text(tr("ssh.help")).font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Label("USB · UDID",systemImage:"cable.connector").frame(minWidth:150)
                                TextField(tr("ssh.port"),text:$model.sshPort).frame(width:80)
                                TextField(tr("ssh.user"),text:$model.sshUser).frame(width:110)
                                Button(tr("common.save"),action:model.saveSSH)
                                Button(tr("ssh.open"),action:model.ssh).buttonStyle(.borderedProminent).tint(appAccent).disabled(!vm.running || !model.validSSH || model.console.running)
                            }
                        }
                        Panel {
                            if ["jb","exp"].contains(vm.variant) {
                            HStack {
                                Button(tr("repair.title"),action:model.repairJBApps)
                                    .disabled(!vm.running || !model.validSSH || model.console.running)
                                Text(tr("repair.help")).font(.caption).foregroundStyle(.secondary)
                            }
                            } else {
                                Label(tr("repair.requires_jb"),systemImage:"info.circle").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Panel {
                            Label(tr("vm.resources"),systemImage:"cpu").font(.headline)
                            HStack {
                                Stepper("\(model.configCPU) CPU",value:$model.configCPU,in:1...max(1,ProcessInfo.processInfo.processorCount)).frame(width:170)
                                Stepper("\(model.configRAM) GB RAM",value:$model.configRAM,in:2...max(2,Int(ProcessInfo.processInfo.physicalMemory/1073741824))).frame(width:200)
                                Spacer(); Button(tr("common.apply"),action:model.configure).disabled(vm.running || model.console.running)
                            }
                            if vm.variant == "?" {
                                Picker(tr("vm.resume_variant"),selection:$model.variant) {
                                    Text("Jailbreak").tag("jb"); Text(tr("variant.regular")).tag("regular"); Text(tr("variant.dev")).tag("dev"); Text(tr("variant.exp")).tag("exp")
                                }
                            }
                            Text(tr("vm.resources_help")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !model.message.isEmpty { Text(tr(model.message)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            }.padding(30)
        }.confirmationDialog(tr("vm.stop_confirm"),isPresented:$confirmStop) {
            Button(tr("vm.stop"),role:.destructive,action:model.stop)
        } message: { Text(tr("vm.stop_warning")) }
    }
}

struct CreateView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: VMModel
    @State private var review = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageTitle(title:tr("create.title"),subtitle:tr("create.subtitle"))
                Panel {
                    Text(tr("create.location")).font(.headline)
                    HStack { Text(model.root).font(.callout).textSelection(.enabled); Spacer(); Button(tr("common.choose_directory"),action:model.chooseRoot) }
                    TextField(tr("create.name"),text:$model.name)
                    if !model.validName { Text(tr("create.name_help")).font(.caption).foregroundStyle(.orange) }
                    Picker(tr("create.firmware"),selection:$model.profile) {
                        Text("iPhone17,3 · iOS 27.0 (24A437)").tag("ios27")
                        ForEach(model.catalog) { entry in Text("\(entry.ios.name) · \(entry.recommendedCloudOS.name)").tag(entry.id) }
                        Text(tr("create.custom")).tag("custom")
                    }
                    Text(tr("create.hardware_note")).font(.caption).foregroundStyle(.secondary)
                    if model.profile == "custom" {
                        HStack { TextField(tr("create.iphone_source"),text:$model.iphoneSource); Button(tr("common.choose_file")) { model.pickSource(iphone:true) } }
                        HStack { TextField(tr("create.cloud_source"),text:$model.cloudSource); Button(tr("common.choose_file")) { model.pickSource(iphone:false) } }
                        Text(tr("create.pair_note")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Panel {
                    Text(tr("create.options")).font(.headline)
                    Picker(tr("create.variant"),selection:$model.variant) {
                        Text("Jailbreak · Sileo / TrollStore (jb)").tag("jb")
                        Text(tr("variant.regular_full")).tag("regular")
                        Text(tr("variant.dev_full")).tag("dev")
                        Text(tr("variant.exp_full")).tag("exp")
                    }
                    Stepper(tr("create.disk_size", model.diskGB),value:$model.diskGB,in:32...512,step:16)
                    Toggle(tr("create.frida"),isOn:$model.frida).disabled(!["jb","exp"].contains(model.variant))
                    Text(tr("create.defaults")).font(.caption).foregroundStyle(.secondary)
                }
                Panel {
                    Text(tr("create.ready")).font(.headline)
                    Text(tr("create.preflight")).foregroundStyle(.secondary)
                    Button { review = true } label: { Label(tr("create.review"),systemImage:"arrow.right.circle.fill") }.buttonStyle(.borderedProminent).tint(appAccent).controlSize(.large).disabled(!model.canCreate)
                    if FileManager.default.fileExists(atPath:model.root + "/VMs/" + model.name) { Text(tr("create.exists")).font(.caption).foregroundStyle(.orange) }
                }
            }.padding(30)
        }.disabled(model.console.running)
        .sheet(isPresented:$review) {
            VStack(alignment:.leading,spacing:20) {
                Text(tr("create.summary")).font(.title2.bold())
                LabeledContent("VM",value:model.name)
                LabeledContent(tr("create.location_label"),value:model.root + "/VMs/" + model.name)
                LabeledContent(tr("create.firmware"),value:tr(model.profileTitle))
                LabeledContent(tr("create.variant"),value:model.variant)
                LabeledContent(tr("create.disk"),value:"\(model.diskGB) GB")
                Text(tr("create.download_note")).foregroundStyle(.secondary)
                HStack { Button(tr("common.back")) { review = false }; Spacer(); Button(tr("create.start")) { review = false; DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { model.install("create") } }.buttonStyle(.borderedProminent).tint(appAccent) }
            }.padding(28).frame(width:620)
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: VMModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack { PageTitle(title:tr("setup.title"),subtitle:tr("setup.subtitle")); Button(tr("common.check"),action:model.checkHost).disabled(model.checking) }
                Panel {
                    if model.checking { ProgressView(tr("setup.checking")) }
                    ForEach(model.checks) { check in
                        HStack(alignment:.top,spacing:12) {
                            Image(systemName:check.good ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(check.good ? appAccent : .orange)
                            VStack(alignment:.leading,spacing:4) { Text(tr(check.id)).font(.headline); Text(tr(check.detail)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                }
                Panel {
                    Text(tr("setup.tools")).font(.headline)
                    HStack {
                        Button(tr("setup.dependencies")) { model.install("dependencies") }.buttonStyle(.borderedProminent).tint(appAccent)
                        Button(tr("setup.xcode"),action:model.chooseXcode)
                        Button(tr("setup.amfi")) { model.install("amfi") }
                    }.disabled(model.console.running)
                    if !model.xcodeDir.isEmpty { Text(model.xcodeDir).font(.caption).foregroundStyle(.secondary) }
                    Text(tr("setup.amfi_note")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(tr("setup.brew")) {
                            guard let script = Bundle.main.path(forResource:"bootstrap-brew",ofType:"sh") else { return }
                            model.console.completion = { model.checkHost() }
                            model.console.start(title:tr("setup.brew_title"),executable:"/bin/bash",args:[script])
                        }.disabled(model.console.running)
                        Link(tr("setup.brew_link"),destination:URL(string:"https://brew.sh")!); Link(tr("setup.xcode_link"),destination:URL(string:"https://developer.apple.com/xcode/")!) }
                }
                Panel {
                    Text(tr("setup.recovery")).font(.headline)
                    Text(tr("setup.recovery_help")).foregroundStyle(.secondary)
                    Text("csrutil enable --without debug\ncsrutil allow-research-guests enable").font(.system(.body,design:.monospaced)).textSelection(.enabled)
                    Text(tr("setup.recovery_warning")).font(.caption).foregroundStyle(.secondary)
                }
                Panel {
                    Text(tr("setup.compatibility")).font(.headline)
                    Text(tr("setup.fairplay")).foregroundStyle(.secondary)
                    Link(tr("setup.upstream"),destination:URL(string:"https://github.com/Lakr233/vphone-cli")!)
                }
            }.padding(30)
        }
    }
}
