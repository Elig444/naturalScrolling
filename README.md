
# naturalScrolling
Seamlessly switch between natural scrolling on Macbook trackpad and traditional mouse scrolling

# Natural Scrolling Auto

A tiny macOS menu-bar agent that automatically turns **natural scrolling off when
an external mouse is connected** and **back on when you're on the trackpad alone** —
so you never have to open System Settings when you dock or undock your MacBook.

## Why it's cheap on CPU & battery

- **Event-driven detection, zero polling.** It registers IOKit device
  *matched* / *terminated* notifications for HID mouse devices
  ([`MouseMonitor.swift`](Sources/NaturalScrollingAuto/MouseMonitor.swift)).
  The process sleeps with ~0% CPU and only wakes when a mouse is attached or removed.
- **No background scanning, no `ioreg`/`system_profiler` subprocesses.**
- **No special permissions.** It only enumerates device *presence*; it never opens
  devices to read input, so macOS does **not** require Accessibility or Input
  Monitoring access.

## How the toggle works

macOS stores natural scrolling in the global preference
`com.apple.swipescrolldirection` (`true` = natural on). Writing that value alone
does **not** apply live — the input system only re-reads it at login. So
[`ScrollDirectionController.swift`](Sources/NaturalScrollingAuto/ScrollDirectionController.swift)
also calls the private `setSwipeScrollDirection(bool)` in
`PreferencePanesSupport.framework` (the same call the Mouse/Trackpad pref pane uses)
and posts `SwipeScrollDirectionDidChangeNotification`, which makes the change take
effect instantly with no logout. The symbol is resolved at runtime with `dlsym`; if
a future macOS removes it, the app degrades gracefully (writes the persistent
default, which applies at next login, and shows a warning in its menu).

## Detecting a *real* mouse

The built-in trackpad also enumerates as a HID "Mouse," so the app excludes it by
requiring a USB/Bluetooth transport and filtering out built-in / trackpad-named
devices. A Magic Mouse counts as a mouse (natural off), matching the "mouse =
traditional scrolling" rule.

## Build & install

Requires the Xcode Command Line Tools (Swift). No full Xcode needed.

```bash
./build-app.sh              # builds build/NaturalScrollingAuto.app
./build-app.sh --install    # also copies to /Applications and launches it
```

Then click the menu-bar icon and enable **Open at Login** so it starts with macOS.

## Menu

- **Mouse / Natural scrolling** status lines
- **Pause automatic switching** — stop reacting to mouse attach/detach
- **Switch to mouse / natural** — manual override (auto-pauses so it isn't undone)
- **Open at Login** — register/unregister via `SMAppService`
- **Quit**

## Test it live

With the app running, plug in (or Bluetooth-connect) a mouse: scrolling should flip
to traditional immediately. Unplug it: scrolling returns to natural. No logout, no
System Settings.
