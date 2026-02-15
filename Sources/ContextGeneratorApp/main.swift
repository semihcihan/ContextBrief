import AppKit
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics

let app = NSApplication.shared
guard
    let firebaseConfigPath = Bundle.module.path(forResource: "GoogleService-Info", ofType: "plist"),
    let firebaseOptions = FirebaseOptions(contentsOfFile: firebaseConfigPath)
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
