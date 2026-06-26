import Foundation

/// Applies the macOS "natural scrolling" setting and makes it take effect
/// *live* (no logout required).
///
/// macOS stores the setting in the global preference
/// `com.apple.swipescrolldirection` (true = natural ON, false = natural OFF).
/// Writing that preference alone does **not** apply live — the input system
/// only re-reads it on login. The Mouse/Trackpad preference pane applies it
/// instantly by calling a private function, `setSwipeScrollDirection(bool)`,
/// in `PreferencePanesSupport.framework`, then posting a distributed
/// notification so other processes (incl. System Settings) stay in sync.
///
/// We resolve that symbol at runtime with `dlsym` so that if Apple ever
/// removes it on a future OS, we degrade gracefully: the persistent default
/// is still written (so the setting is correct after the next login) and we
/// log a warning, rather than crashing.
final class ScrollDirectionController {

    private typealias SetSwipeScrollDirectionFn = @convention(c) (Bool) -> Void

    private let key = "com.apple.swipescrolldirection" as CFString
    private let setSwipeScrollDirection: SetSwipeScrollDirectionFn?

    /// True if the private live-apply function was found on this system.
    let liveApplyAvailable: Bool

    init() {
        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "setSwipeScrollDirection") {
            setSwipeScrollDirection = unsafeBitCast(sym, to: SetSwipeScrollDirectionFn.self)
            liveApplyAvailable = true
        } else {
            setSwipeScrollDirection = nil
            liveApplyAvailable = false
            NSLog("[NaturalScrollingAuto] setSwipeScrollDirection unavailable — live toggle disabled, persistent default only")
        }
    }

    /// Current value of the natural-scrolling preference (true = natural ON).
    var isNaturalEnabled: Bool {
        let value = CFPreferencesCopyValue(key,
                                           kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser,
                                           kCFPreferencesCurrentHost)
        return (value as? Bool) ?? true // macOS default is natural ON
    }

    /// Set natural scrolling on/off, applying immediately when possible and
    /// always persisting so the choice survives reboot.
    func setNaturalScrolling(enabled: Bool) {
        // 1. Live apply (private framework) — no logout needed.
        setSwipeScrollDirection?(enabled)

        // 2. Persist to the global domain so the value is correct on next login
        //    and matches what System Settings shows.
        CFPreferencesSetValue(key,
                              enabled as CFBoolean,
                              kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesCurrentHost)

        // 3. Tell the rest of the system the setting changed.
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
