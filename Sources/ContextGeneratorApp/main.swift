import AppKit
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics

func firebaseConfigPath() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let configuredPath = environment["GOOGLE_SERVICE_INFO_PLIST_PATH"], !configuredPath.isEmpty {
        return configuredPath
    }
    return Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
}

let app = NSApplication.shared
guard
    let configPath = firebaseConfigPath(),
    let firebaseOptions = FirebaseOptions(contentsOfFile: configPath)
else {
    fatalError("Missing or invalid Firebase configuration file.")
}
FirebaseApp.configure(options: firebaseOptions)
Analytics.setAnalyticsCollectionEnabled(true)
EventTracker.shared.track(.appLaunch)
Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
let delegate = MenuBarAppController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
