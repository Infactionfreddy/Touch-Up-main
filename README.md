# Touch-Up
**Universal user-level driver to support touchscreens on macOS**
<hr/>

Most current touchscreens work with Microsoft Windows out-of-the-box as they implement a standardized communication via USB HID. However, nothing happens when connecting these screens to a Mac.
The goal of Touch Up was to provide a simple, general-purpose driver that enables plug-and-play support for touchscreens on macOS. 
The code in this repository provides a user-space driver that reads and processes the HID data into a set of touches and different utilities to inject mouse events into the system.

## What can you do with this App?
The Touch Up **utility app** allows you to control your Mac with any connected touch screen. Touch Up supports clicks, dragging, scrolling, and pinch-to-zoom.
While the behavior of the driver is customizable, the default setting was inspired by iPadOS:

- Tap anywhere on the screen to click objects
- Scroll content by flicking over the screen
- Drag contents by briefly resting your finger before moving it
- Zoom content by pinching two fingers
- Secondary clicks can be performed with two fingers
- You can even enable touching a window to move it to the front like Stage Manager on iPadOS does


### Installing the App
- Compile the app or [download the latest notarized build here](https://github.com/shueber/Touch-Up/releases).
- If you wish, move the app into your Applications folder and add it as a Login item.
- Launch it and allow Accessibility access.
- Plug in your touchscreen and start touching.


### Compatibility

#### macOS Requirements
- **macOS 10.15 Catalina or later** recommended
- Requires Accessibility permissions for touch input injection
- Works with both Intel and Apple Silicon Macs

#### Supported Hardware
Touch Up should work with any touchscreen that also works with Windows via USB HID.

##### Tested Touchscreens
- Iiyama TF3222MC and T2336MSC-B2
- 3M C4667PW
- **ELAN Touchscreens (Vendor ID: 0x04F3)** - Enhanced support with automatic detection

##### ELAN Touchscreen Support
This version includes **enhanced support** for ELAN touchscreens with advanced features:

**Features:**
- ✅ **Automatic device detection** (Vendor ID: 0x04F3)
- ✅ **Extended HID device matching** for TouchScreen and Touch digitizer types
- ✅ **Position-based touch ID deduplication** for Hybrid-Mode hardware
- ✅ **Multi-display support** with automatic calibration
- ✅ **Smart ID reuse** to keep touch IDs bounded (0-9 range)
- ✅ **Detailed debug logging** for troubleshooting (`/tmp/touchup_touch_events.log`)

**Touch Handling:**
- Supports up to 10 simultaneous touch points
- Touch IDs automatically reset when all fingers are lifted
- Stable touch tracking with 5% position matching threshold
- Filters invalid positions to prevent phantom touches

**Calibration:**
- Screen calibration persists across sessions (`~/Library/Application Support/Touch Up/screen_*.json`)
- Calibrated displays prioritized for touch input
- Support for both primary and secondary displays

**Troubleshooting:**
If your ELAN touchscreen is not detected:
1. Launch Touch Up
2. Open Console.app (Applications > Utilities)
3. Filter for "Touch" or "ELAN" in the search bar
4. Plug in your ELAN touchscreen
5. Look for messages like "ELAN Touchscreen detected!" with device information
6. Check `/tmp/touchup_touch_events.log` for detailed touch event debugging




## The *TouchUpCore* Framework
Game developers, researchers, and others who need access to all touch data can also benefit from this project by integrating the TouchUpCore **framework** themselves. It provides simple access to all touches recognized on the touch surface, simplifying multitouch prototype development in macOS.

The Touch Up app itself is an example of integrating the TouchUpCore framework. You can have a look at the *DebugView* to see how you can visualize the different touch points. Remember that your app needs an Entitlement to access USB if running in the Sandbox.
