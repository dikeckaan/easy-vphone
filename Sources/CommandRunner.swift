import Foundation
import Darwin

struct CommandResult { let code: Int32; let output: String }
let toolPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
let vphoneCLI = "/Applications/vphone-cli.app/Contents/MacOS/vphone-cli"

/// Reusable cancellation token; each user operation gets its own token.
final class CommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

func capture(_ executable: String, _ args: [String], env: [String:String] = [:],
             timeout: TimeInterval = 30, cancellation: CommandCancellation? = nil) -> CommandResult {
    if cancellation?.cancelled == true { return CommandResult(code:130,output:"Cancelled.") }
    let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = args
    p.environment = ProcessInfo.processInfo.environment.merging(["PATH":toolPATH]) { _, n in n }.merging(env) { _, n in n }
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return CommandResult(code:-1,output:error.localizedDescription) }
    // Nonblocking reads also bound waits when a descendant retains stdout.
    let fd = pipe.fileHandleForReading.fileDescriptor
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    var data = Data(); var forced: Int32?; var stopAt: TimeInterval?
    var buffer = [UInt8](repeating:0,count:16384)
    while true {
        let count = read(fd, &buffer, buffer.count)
        if count > 0 { data.append(contentsOf:buffer.prefix(count)); if data.count > 2_000_000 { data.removeFirst(data.count - 2_000_000) } }
        let now = ProcessInfo.processInfo.systemUptime
        if forced == nil && (cancellation?.cancelled == true || now >= deadline) {
            forced = cancellation?.cancelled == true ? 130 : 124; stopAt = now
            if p.isRunning { p.terminate() }
        }
        if let stopAt, now - stopAt >= 1 {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            break
        }
        if !p.isRunning && count <= 0 { break }
        if count <= 0 { Thread.sleep(forTimeInterval:0.02) }
    }
    p.waitUntilExit(); try? pipe.fileHandleForReading.close()
    var output = String(decoding:data,as:UTF8.self)
    if let forced { output += forced == 124 ? "\nOperation timed out." : "\nCancelled." }
    return CommandResult(code:forced ?? p.terminationStatus,output:output)
}
