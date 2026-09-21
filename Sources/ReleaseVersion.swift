import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let chunks = value.split(separator:".",omittingEmptySubsequences:false)
        guard chunks.count == 3, chunks.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              chunks.allSatisfy({Int($0) != nil}) else { return nil }
        parts = chunks.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
struct AppRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: String }
    let tag_name: String
    let draft: Bool
    let assets: [Asset]
    var version: ReleaseVersion? { ReleaseVersion(tag_name) }
    var downloadURL: URL? {
        guard let asset = assets.first(where:{$0.name == "easy-vphone-\(tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name)-arm64.zip"}),
              let url = URL(string:asset.browser_download_url), url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/dikeckaan/easy-vphone/releases/download/") else { return nil }
        return url
    }
    static func newest(in releases: [Self], current: String) -> Self? {
        guard let installed = ReleaseVersion(current) else { return nil }
        return releases.filter { !$0.draft && $0.downloadURL != nil && ($0.version.map { $0 > installed } ?? false) }
            .max { $0.version! < $1.version! }
    }
}
