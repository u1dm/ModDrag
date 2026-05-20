# ModDrag

ModDrag is a lightweight Swift menu bar app that lets you move and resize macOS windows by holding a side mouse button plus configurable modifiers. It relies on public accessibility APIs, standard mouse button events, and an optional Logitech HID fallback.

## Features

-   Drag with `Cmd` + custom mouse key, resize with `Ctrl+Cmd` + the same custom mouse key, and maximize with a double-tap
-   Menu bar controls for recording independent move/resize/maximize shortcuts, button numbers, minimum window size, and HID fallback
-   Builds as a normal `.app` bundle so it can be launched from Spotlight and run without a terminal
-   Smooth window movement with timer-coalesced updates for responsive tracking without unnecessary CPU load
-   Seamless switching between dragging and resizing while keeping the same window captured
-   Safety controls: press the `Esc` key to cancel the current action or `Ctrl+C` to terminate the app
-   Built-in guards that skip fullscreen or minimised windows and enforce a minimum window size

## Install

### Homebrew

The recommended install path is the project tap:

```bash
brew install u1dm/tap/moddrag
```

That installs the `mod-drag` CLI and a `ModDrag.app` bundle under the Homebrew prefix. To make the app launchable from Spotlight, copy the app bundle to `/Applications`:

```bash
cp -R "$(brew --prefix moddrag)/ModDrag.app" /Applications/
open /Applications/ModDrag.app
```

After the first launch, grant Accessibility access to **ModDrag** in **System Settings -> Privacy & Security -> Accessibility**. Once it is in `/Applications`, Spotlight can launch it like any other app, and it keeps running as a background menu bar app.

### Homebrew Core

`brew install moddrag` only works after a formula is accepted into `Homebrew/homebrew-core`. ModDrag currently ships through `u1dm/tap` because new, small, self-submitted projects are usually expected to live in a tap first. When the project has enough public usage and release history, the formula can be proposed for Homebrew core.

## Build

```bash
swiftc -O -parse-as-library \
    -framework AppKit \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -framework IOKit \
    -module-cache-path ./.module-cache \
    main.swift -o mod-drag
```

If the compiler reports that it cannot write the Swift module cache, re-run the command with sufficient permissions (the tool needs to write to `~/Library/Developer/Xcode/DerivedData` or `~/.cache/clang/ModuleCache`).

Build the Spotlight-launchable app bundle:

```bash
make app
```

Install it into `/Applications`:

```bash
make install-app
```

## Usage

1. **Run the binary**

    ```bash
    ./mod-drag
    ```

    For normal use, launch `/Applications/ModDrag.app` from Spotlight or Finder. ModDrag shows a menu bar icon while it is running. Use its menu to change shortcuts, minimum window size, HID fallback, or quit the app.

2. **Grant accessibility access** (first run only and if needed)

    - Open **System Settings → Privacy & Security → Accessibility**
    - Press the **"+"** button and add `ModDrag.app` from `/Applications`
    - Restart ModDrag after granting access

3. **Interact**

    - Hold `Cmd` + the custom mouse key and move the mouse to relocate the window under the cursor
    - Hold `Ctrl+Cmd` + the same custom mouse key and move the mouse to resize the captured window
    - Double-tap `Cmd` + the custom mouse key to maximize the window under the cursor; double-tap again to restore it
    - If the side button does not trigger, open the menu bar icon and try the button submenu for the specific action
    - Press `Esc` to abandon the current operation
    - Use the menu bar icon to quit ModDrag

Console logs show the current state (`Idle`, `Armed`, `Dragging`, `Resize Armed`, `Resizing`) so you can confirm what the tool is doing at any moment.

## Default Shortcuts

Runtime shortcut settings are stored in macOS `UserDefaults` and can be changed from the menu bar icon:

-   Move: `Cmd + Button 3`
-   Resize: `Ctrl+Cmd + Button 3`
-   Maximize: double-tap `Cmd + Button 3`
-   Minimum window size: `100x100`
-   Logitech HID fallback: enabled

Use **Record Move Shortcut**, **Record Resize Shortcut**, or **Record Maximize Shortcut** to bind a custom combination. After selecting a record item, press the desired keyboard key/modifiers plus the side mouse button. For example, `Shift+Space+Button 4` or `Cmd+Button 3`.

Each action stores its own button and keyboard combination. Recording **Move** no longer changes **Resize** or **Maximize**.

The optional HID fallback defaults live in `WindowDraggerConfiguration.default` inside `main.swift`:

```swift
static let `default` = WindowDraggerConfiguration(
    customKey: CustomKeyConfiguration(
        vendorID: 0x046D,
        productID: nil,
        locationID: nil,
        productSubstring: nil,
        prefix: [0x11, 0x02, 0x0D, 0x00, 0x00],
        stateOffset: 0,
        reportBufferLength: 512,
        logOpenErrors: false
    ),
    emergencyStopKeyCode: 53,
    minimumWindowSize: CGSize(width: 100, height: 100),
    updateInterval: 1.0 / 120.0
)
```

-   `vendorID: 0x046D` targets Logitech devices by default.
-   `prefix` and `stateOffset` identify the side/custom key in the HID input report.
-   `emergencyStopKeyCode` is the macOS key code for the emergency stop key (`53` is `Esc`).
-   The menu bar **Minimum Window Size** option prevents collapsing a window below the selected size.

### Finding key codes

macOS key codes differ from printable characters. Useful references:

-   49 – Space
-   53 – Esc
-   96 – F5
-   97 – F6
-   98 – F7
-   99 – F8

You can add new codes to the `keyName(for:)` helper if you use additional keys and want them to appear nicely in the console output.

## Customising Behaviour

-   Use the menu bar icon to change each action's button number and modifiers at runtime.
-   Adjust the `customKey` HID matching values only if you need the Logitech fallback for a different raw report.
-   Modify `updateInterval` to raise or lower the refresh rate. Lower values increase CPU usage but make movement more responsive.

Rebuild the binary after any changes:

```bash
swiftc -O -parse-as-library \
    -framework AppKit \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -framework IOKit \
    -module-cache-path ./.module-cache \
    main.swift -o mod-drag
```

## Troubleshooting

-   **The app exits immediately** – ensure the binary has accessibility permission. The tool prints detailed instructions when the permission is missing.
-   **Spotlight does not find ModDrag** – run `make install-app` or copy `ModDrag.app` into `/Applications`, then launch it once.
-   **The side button does not work** – enable `--log`, press the side button, and check the logged button number. Then choose the matching button value for the action in the menu bar menu.
-   **A window does not move** – some system or sandboxed apps disallow programmatic movement; the tool skips those windows.
-   **Logs show “Failed to move/resize window”** – the app probably rejected the accessibility command. Releasing and re-engaging the shortcut usually resets the state.
