import SwiftUI
import AppKit
import Combine

func pythonPath() -> String {
    for path in ["/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3", "/usr/bin/python3"] {
        if FileManager.default.isExecutableFile(atPath:path) { return path }
    }
    return "/usr/bin/python3"
}

@MainActor final class ConsoleModel: ObservableObject {
    @Published var title = tr("console.log")
    @Published var output = ""
    @Published var running = false
    @Published var presented = false
    @Published var reply = ""
    @Published var sensitive = false
    @Published var exitCode: Int32?
    private var process: Process?
    private var input: Pipe?
    private var secrets: [String] = []
    var completion: (() -> Void)?

    func start(title: String, executable: String, args: [String], env: [String:String] = [:], sensitive: Bool = false) {
        guard !running else { presented = true; return }
        self.title = title; output = ""; reply = ""; secrets = []; exitCode = nil
        self.sensitive = sensitive; presented = true
        guard let bridge = Bundle.main.path(forResource:"easy-vphone-terminal",ofType:nil) else { output = tr("console.missing"); return }
        let p = Process(); p.executableURL = URL(fileURLWithPath:bridge); p.arguments = [executable] + args
        p.environment = ProcessInfo.processInfo.environment.merging(["PATH":toolPATH,"PYTHONUNBUFFERED":"1","NO_COLOR":"1"]) { _, n in n }.merging(env) { _, n in n }
        let incoming = Pipe(); let outgoing = Pipe(); input = incoming
        p.standardInput = incoming; p.standardOutput = outgoing; p.standardError = outgoing
        process = p; running = true
        do { try p.run() } catch { running = false; output = error.localizedDescription; return }
        // Drain on one queue so final output is delivered before completion.
        DispatchQueue.global(qos:.utility).async { [weak self] in
            while true {
                let data = outgoing.fileHandleForReading.availableData
                if data.isEmpty { break }
                let text = String(decoding:data,as:UTF8.self)
                DispatchQueue.main.async { self?.append(text) }
            }
            p.waitUntilExit()
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false; self.exitCode = p.terminationStatus
                self.input = nil; self.process = nil; self.reply = ""; self.secrets = []
                self.completion?(); self.completion = nil
            }
        }
    }
    private func append(_ text: String) {
        let clean = text.replacingOccurrences(of:"\u{001B}\\[[0-?]*[ -/]*[@-~]",with:"",options:.regularExpression)
            .replacingOccurrences(of:"\r",with:"\n")
        output += clean
        for secret in secrets where !secret.isEmpty { output = output.replacingOccurrences(of:secret,with:"••••••") }
        if output.count > 90000 { output = String(output.suffix(70000)) }
    }
    func send() {
        guard running, let input else { return }
        let value = reply; reply = ""
        // All input is masked in the UI. Do not echo credentials or put them in argv.
        if !value.isEmpty { secrets.append(value) }
        try? input.fileHandleForWriting.write(contentsOf:Data((value + "\n").utf8))
    }
    func interrupt() { try? input?.fileHandleForWriting.write(contentsOf:Data([3])) }
    func cancel() { process?.terminate() }
    func clear() { if !running { output = ""; secrets = [] } }
}

struct ConsoleView: View {
    @EnvironmentObject var preferences: InterfacePreferences
    @ObservedObject var model: ConsoleModel
    @State private var confirmCancel = false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Image(systemName:"terminal.fill").foregroundStyle(appAccent)
                Text(tr(model.title)).font(.title2.bold()); Spacer()
                if model.running { ProgressView().controlSize(.small) }
                else if let code = model.exitCode { Label(code == 0 ? tr("console.done") : tr("console.exit", code),systemImage:code == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle").foregroundStyle(code == 0 ? .green : .orange) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.output.isEmpty ? tr("console.starting") : model.output).font(.system(size:12,design:.monospaced))
                        .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    Color.clear.frame(height:1).id("end")
                }.padding(14).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                    .onChange(of:model.output) { _, _ in proxy.scrollTo("end",anchor:.bottom) }
            }
            if model.running {
                Text(tr("console.input_help")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField(tr("console.input"),text:$model.reply).onSubmit(model.send)
                    Button(tr("console.send"),action:model.send).keyboardShortcut(.return,modifiers:[])
                    Button("Ctrl+C",action:model.interrupt)
                }
            }
            HStack {
                if model.running { Button(tr("console.stop"),role:.destructive) { confirmCancel = true } }
                else { Button(tr("console.clear"),action:model.clear) }
                Spacer()
                Button(model.running ? tr("console.background") : tr("common.close")) { model.presented = false }
            }
        }.padding(24).frame(width:850,height:610)
        .confirmationDialog(tr("console.stop_confirm"),isPresented:$confirmCancel) {
            Button(tr("common.stop"),role:.destructive,action:model.cancel)
        } message: { Text(tr("console.stop_warning")) }
    }
}
