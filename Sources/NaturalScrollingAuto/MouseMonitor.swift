import Foundation
import IOKit
import IOKit.hid

/// Detects whether an external mouse is currently connected, and notifies on
/// change. Fully event-driven: it registers IOKit "device matched" /
/// "device terminated" notifications for HID mouse devices, so the process
/// sleeps with ~zero CPU and only wakes when a device is attached or removed.
/// No polling, and — because we only enumerate device *presence* and never
/// open devices to read input — no Input Monitoring / Accessibility
/// permission is required.
final class MouseMonitor {

    private let onChange: (Bool) -> Void
    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0

    /// Whether at least one external mouse is currently connected.
    private(set) var isMouseConnected = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else {
            NSLog("[NaturalScrollingAuto] failed to create IONotificationPort")
            return
        }
        // Deliver callbacks on the main queue so UI updates are safe.
        IONotificationPortSetDispatchQueue(notifyPort, DispatchQueue.main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        let callback: IOServiceMatchingCallback = { ctx, iterator in
            let monitor = Unmanaged<MouseMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            monitor.drain(iterator)   // re-arm the notification
            monitor.recount()         // recompute connected state
        }

        // Device attached. (IOServiceAddMatchingNotification consumes one
        // reference on the matching dict, so each call gets its own.)
        IOServiceAddMatchingNotification(notifyPort,
                                         kIOMatchedNotification,
                                         mouseMatchingDictionary(),
                                         callback,
                                         context,
                                         &matchedIterator)
        drain(matchedIterator)

        // Device removed.
        IOServiceAddMatchingNotification(notifyPort,
                                         kIOTerminatedNotification,
                                         mouseMatchingDictionary(),
                                         callback,
                                         context,
                                         &terminatedIterator)
        drain(terminatedIterator)

        recount() // establish initial state
    }

    // MARK: - Matching

    /// Matches HID devices whose primary usage is Generic Desktop → Mouse.
    private func mouseMatchingDictionary() -> CFMutableDictionary {
        let dict = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        dict[kIOHIDDeviceUsagePageKey] = 0x01 // Generic Desktop
        dict[kIOHIDDeviceUsageKey] = 0x02     // Mouse
        return dict as CFMutableDictionary
    }

    /// Full re-scan of currently-present mouse devices. Cheap and only runs on
    /// an attach/remove event (or at launch), so it stays event-driven.
    private func recount() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                  mouseMatchingDictionary(),
                                                  &iterator)
        var count = 0
        if result == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if isExternalMouse(service) { count += 1 }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        let connected = count > 0
        if connected != isMouseConnected {
            isMouseConnected = connected
            onChange(connected)
        }
    }

    /// Decides whether a matched HID device is a real *external* mouse.
    ///
    /// This needs care: the built-in trackpad enumerates with
    /// PrimaryUsage = 2 (Mouse) just like a real mouse, and on some Macs it
    /// has no `BuiltIn` property at all — so we can't rely on that flag alone.
    /// The robust positive signal is the transport: external mice arrive over
    /// USB or Bluetooth, while the internal trackpad uses FIFO/SPI. We require
    /// a USB/Bluetooth transport and additionally exclude anything flagged
    /// built-in or named like a trackpad.
    private func isExternalMouse(_ service: io_service_t) -> Bool {
        if let builtIn = property(service, kIOHIDBuiltInKey) as? Bool, builtIn {
            return false
        }
        if let name = property(service, kIOHIDProductKey) as? String,
           name.localizedCaseInsensitiveContains("trackpad") {
            return false
        }
        // Positive signal: only count external transports.
        let transport = (property(service, kIOHIDTransportKey) as? String)?.lowercased() ?? ""
        let external = transport.contains("usb")
            || transport.contains("bluetooth")
            || transport.contains("bt")
        return external
    }

    private func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service,
                                        key as CFString,
                                        kCFAllocatorDefault,
                                        0)?.takeRetainedValue()
    }

    /// Iterate an iterator to completion, releasing each object. Required to
    /// re-arm an IOKit matching notification.
    private func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
