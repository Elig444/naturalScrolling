import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar agent: no Dock icon, no main window. (Reinforced by LSUIElement in
// the bundle's Info.plist when run as a packaged .app.)
app.setActivationPolicy(.accessory)
app.run()
