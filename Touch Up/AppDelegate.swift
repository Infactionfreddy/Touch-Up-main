//
//  AppDelegate.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 03.02.23.
//

import Cocoa
import SwiftUI
import Combine


@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let model = TouchUp()
    
    
    var statusItem: NSStatusItem!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var activationMenuItem: NSMenuItem!
    
    var observers = [AnyCancellable]()
    
    
    
    lazy var settingsWindow: SettingsWindow = {
        return SettingsWindow.window(model: self.model)
    }()
    
    lazy var debugOverlay: DebugOverlay = {
        return DebugOverlay.overlay(model: self.model)
    }()
    
    @IBAction func toggleActivationMenu(_ sender: Any) {
        self.model.isPublishingMouseEventsEnabled.toggle()
    }
    
    
    
    //MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem.menu = self.statusMenu
        
        self.observers.append(
            self.model.$connectionState
                .receive(on: DispatchQueue.main)
                .sink{status in
                    DispatchQueue.main.async {
                        self.statusItem.button?.image = status.image
                    }
                    
                }
        )
        
        self.observers.append(
            self.model.$isPublishingMouseEventsEnabled
                .receive(on: DispatchQueue.main)
                .sink{
                    self.activationMenuItem.state = $0 ? .on : .off
                    // Synchronisiere auch direkt zum touchManager
                    self.model.touchManager.postMouseEvents = $0
                }
        )
        
        // FORCE postMouseEvents auf true - kritisch!
        print("[AppDelegate] Erzwinge postMouseEvents=true vor start()")
        self.model.isPublishingMouseEventsEnabled = true
        self.model.touchManager.postMouseEvents = true
        
        // First check accessibility access (ohne Dialog)
        self.model.checkAccessibilityAccessGranted()
        
        // Start HID manager - wird blockiert wenn postMouseEvents = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("[AppDelegate] Starte touchManager - postMouseEvents=\(self.model.touchManager.postMouseEvents)")
            self.model.touchManager.start()
        }
        
        // Falls Accessibility nicht gewährt ist, zeige Warning und polle
        if !model.isAccessibilityAccessGranted {
            self.showAccessibilityPermissionDialog()
            // Polle alle 3 Sekunden bis Berechtigung erteilt
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
                guard let self = self else { 
                    timer.invalidate()
                    return 
                }
                self.model.checkAccessibilityAccessGranted()
                print("[AccessibilityPoller] Status: \(self.model.isAccessibilityAccessGranted)")
                if self.model.isAccessibilityAccessGranted {
                    timer.invalidate()
                    print("[AccessibilityPoller] ✅ Berechtigung nun aktiv!")
                }
            }
        } else {
            print("[AppDelegate] ✅ Accessibility sofort aktiv")
        }
        
        #if DEBUG
//        self.showPreferences(nil)
        self.showDebugOverlay()
        #endif
    }
    
    private func showAccessibilityPermissionDialog() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Touch Up benötigt Zugriff auf Eingabehilfen (Accessibility) um auf den Touchscreen zuzugreifen.

        Klicken Sie auf "Einstellungen öffnen", um:
        1. Systemeinstellungen zu öffnen
        2. Datenschutz & Sicherheit → Eingabehilfen
        3. Das Schloss klicken und entsperren
        4. + Button klicken und "Touch Up" hinzufügen
        5. Diese Anwendung neu starten
        """
        alert.addButton(withTitle: "Einstellungen öffnen")
        alert.addButton(withTitle: "Später")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Preferences to Accessibility
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        self.model.touchManager.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    
    @IBAction func showPreferences(_ sender: Any?) {
        self.settingsWindow.makeVisible()
    }
    
    func showDebugOverlay() {
        let preState = self.model.isPublishingMouseEventsEnabled
        self.model.isPublishingMouseEventsEnabled = false
        DebugOverlay.completion = {[unowned self] in
            self.debugOverlay.close()
            self.model.isPublishingMouseEventsEnabled = preState
        }
        
        self.debugOverlay.makeVisible()
    }
}



class SettingsWindow: NSWindow {
    
    var model: TouchUp?
    
    static func window(model: TouchUp) -> SettingsWindow {
        let vc = NSHostingController(rootView: SettingsView(model:model))
        let window = SettingsWindow(contentRect: .zero,
                                    styleMask: [.closable, .titled, .fullSizeContentView, .resizable],
                                    backing: .buffered,
                                    defer: true,
                                    screen: nil)
        
        window.title = "Touch Up Settings"
        window.tabbingMode = .disallowed
        window.model = model
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        let windowController = NSWindowController(window: window)
        
        windowController.contentViewController = vc
        return window
    }
    
    override func close() {
        self.model?.savePreferences()
        NSApp.stopModal()
        super.close()
    }
    
    func makeVisible() {
        let alreadyOnScreen = self.isVisible
        
        self.setIsVisible(true)
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !alreadyOnScreen {
            self.center()
        }
        
    }
}



class DebugOverlay: NSWindow {
    
    var model: TouchUp?
    static var completion: (()->Void)?
    
    static func overlay(model: TouchUp) -> DebugOverlay {
        let vc = NSHostingController(rootView: DebugView(model:model, closeAction: {
            DebugOverlay.completion?()
        }))
        
        let window = DebugOverlay(contentRect: .zero,
                                    styleMask: [.resizable, .miniaturizable, .fullSizeContentView],
                                    backing: .buffered,
                                    defer: true,
                                    screen: nil)
        
        window.title = "Touches"
        window.tabbingMode = .disallowed
        window.model = model
        
        let windowController = NSWindowController(window: window)
        
        windowController.contentViewController = vc
        
        return window
    }
    
    
    func makeVisible() {
        
        self.setIsVisible(true)
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if let controller = self.contentViewController {
            if let screen = model?.connectedTouchscreen?.systemScreen() {
                self.level = .screenSaver // prevents notifications from coming in
                let presentationOptions: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]
                
                let options: [NSView.FullScreenModeOptionKey : NSNumber] = [
                    .fullScreenModeApplicationPresentationOptions : NSNumber(value: presentationOptions.rawValue),
                    .fullScreenModeWindowLevel : NSNumber(value: kCGNormalWindowLevel),
                    .fullScreenModeAllScreens : NSNumber(booleanLiteral: false)
                ]
                self.setIsVisible(false)
                controller.view.enterFullScreenMode(screen, withOptions: options)
            }
        }
    }
    
    override func close() {
        if let controller = self.contentViewController {
            self.level = .normal
            self.setIsVisible(true)
            controller.view.exitFullScreenMode(options: nil)
        }
        super.close()
    }
}
