import AppKit
import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.session)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

/// Owns the wheel for the life of the process rather than for the life of a window:
/// with the main window closed the app keeps running and the wheel keeps responding
/// to modifier-key file drags.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = WheelSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
