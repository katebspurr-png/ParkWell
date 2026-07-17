import Foundation

/// Backend configuration. Replace the placeholders with your Supabase
/// project's URL and anon (publishable) key — the anon key is safe to ship in
/// the app; row-level security on the backend makes all tables read-only.
///
/// For per-developer overrides without committing keys, add a
/// `Config.local.swift` (gitignored) that redefines these via an extension.
enum Config {
    static let supabaseURL = URL(string: "https://YOUR-PROJECT-REF.supabase.co")!
    static let supabaseAnonKey = "YOUR-SUPABASE-ANON-KEY"
}
