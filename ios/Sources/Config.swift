import Foundation

/// What this app is, from Info.plist (written by project.yml from scripts/app.conf).
enum AppConfig {
    private static func s(_ key: String) -> String { (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "" }
    /// Default control server (Headscale). Headscale sends the browser to oidc.m-we.org (realm mwe) for single sign-on.
    static let defaultServer = s("MeweControlURL").isEmpty ? "https://hs.m-we.org" : s("MeweControlURL")
    static let oidcIssuer = s("MeweOidcIssuer")
    static let tailscaleAppURL = "https://apps.apple.com/app/tailscale/id1470499037"

    private static let key = "server_url"
    static var server: String {
        get { UserDefaults.standard.string(forKey: key) ?? defaultServer }
        set {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if v.isEmpty || v == defaultServer { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(v, forKey: key) }
        }
    }
}
