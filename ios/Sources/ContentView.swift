import AuthenticationServices
import SwiftUI

/// MeWeTail for iOS: points the Tailscale client at the MeWe server (hs.m-we.org, Headscale) and signs in through it with oidc.m-we.org.
/// The system VPN itself on iOS is a Network Extension; this app opens the server's sign-in page and hands the server address to the Tailscale app.
struct ContentView: View {
    @State private var server = AppConfig.server
    @State private var note = ""
    @State private var session: ASWebAuthenticationSession?
    private let anchor = Anchor()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server"), footer: Text("Sign-in uses the server's single sign-on (oidc.m-we.org).")) {
                    TextField("https://hs.m-we.org", text: $server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    HStack {
                        Button("Save") { AppConfig.server = server; server = AppConfig.server; note = "Saved." }
                        Spacer()
                        Button("Default") { AppConfig.server = ""; server = AppConfig.server; note = "" }
                    }
                }
                Section(header: Text("Account")) {
                    Button("Sign in with MeWe (oidc.m-we.org)") { signIn() }
                    Button("Open server in Safari") { open(server) }
                }
                Section(header: Text("Connect this iPhone")) {
                    Text("1. Install the Tailscale app.\n2. In Tailscale: Settings → Use alternate server → \(server).\n3. Sign in with your MeWe account.")
                        .font(.footnote)
                    Button("Copy server address") { UIPasteboard.general.string = server; note = "Copied." }
                    Button("Get the Tailscale app") { open(AppConfig.tailscaleAppURL) }
                }
                if !note.isEmpty { Section { Text(note).font(.footnote).foregroundColor(.secondary) } }
            }
            .navigationTitle("MeWeTail")
        }.navigationViewStyle(.stack)
    }

    private func open(_ s: String) { if let u = URL(string: s) { UIApplication.shared.open(u) } }

    /// Opens the server in the system browser sheet; Headscale forwards to oidc.m-we.org, which shares the single sign-on session across mewe apps.
    private func signIn() {
        guard let url = URL(string: server) else { note = "Invalid server address."; return }
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, _ in }
        s.presentationContextProvider = anchor
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
