import Foundation
@main struct Tests {
    static func main() {
        let success = capture("/bin/echo",["hello"])
        precondition(success.code == 0 && success.output.contains("hello"))
        let start = Date()
        let timeout = capture("/bin/sleep",["10"],timeout:0.15)
        precondition(timeout.code == 124 && Date().timeIntervalSince(start) < 3)
        let token = CommandCancellation()
        DispatchQueue.global().asyncAfter(deadline:.now()+0.15) { token.cancel() }
        let cancelled = capture("/bin/sleep",["10"],timeout:20,cancellation:token)
        precondition(cancelled.code == 130)
        let before = CommandCancellation(); before.cancel()
        precondition(capture("/usr/bin/false",[],cancellation:before).code == 130)
        precondition(capture("/usr/bin/false",[]).code == 1)
        precondition(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.0")!)
        precondition(ReleaseVersion("v0.3.0") == ReleaseVersion("0.3.0"))
        precondition(ReleaseVersion("0.3.0-beta") == nil)
        let good = AppRelease(tag_name:"v0.4.0",draft:false,assets:[.init(name:"easy-vphone-0.4.0-arm64.zip",browser_download_url:"https://github.com/dikeckaan/easy-vphone/releases/download/v0.4.0/easy-vphone-0.4.0-arm64.zip")])
        let draft = AppRelease(tag_name:good.tag_name,draft:true,assets:good.assets)
        let bad = AppRelease(tag_name:"v0.5.0",draft:false,assets:[.init(name:"easy-vphone-0.5.0-arm64.zip",browser_download_url:"https://example.com/fake.zip")])
        precondition(AppRelease.newest(in:[draft,bad,good],current:"0.3.0")?.tag_name == "v0.4.0")
        precondition(AppRelease.newest(in:[good],current:"0.4.0") == nil)
        print("Commands and update selection: 10 checks passed")
    }
}
