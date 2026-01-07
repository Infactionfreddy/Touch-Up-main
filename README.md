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
Touch Up should work with any touchscreen that also works with Windows.
We used the following screens for testing:

- Iiyama TF3222MC and T2336MSC-B2
- 3M C4667PW
- **ELAN Touchscreens (Vendor ID: 0x04F3)** - Enhanced support with automatic detection

#### ELAN Touchscreen Support
This version includes enhanced support for ELAN touchscreens:
- Automatic detection of ELAN devices (Vendor ID: 0x04F3)
- Extended HID device matching for both TouchScreen and Touch digitizer types
- Detailed debug logging for ELAN device identification
- If your ELAN touchscreen is not detected, check Console.app for device detection messages

To verify ELAN device detection:
1. Launch Touch Up
2. Open Console.app (found in Applications > Utilities)
3. Filter for "Touch" or "ELAN" in the search bar
4. Plug in your ELAN touchscreen
5. Look for messages like "ELAN Touchscreen detected!" with device information




## The *TouchUpCore* Framework
Game developers, researchers, and others who need access to all touch data can also benefit from this project by integrating the TouchUpCore **framework** themselves. It provides simple access to all touches recognized on the touch surface, simplifying multitouch prototype development in macOS.

The Touch Up app itself is an example of integrating the TouchUpCore framework. You can have a look at the *DebugView* to see how you can visualize the different touch points. Remember that your app needs an Entitlement to access USB if running in the Sandbox.
