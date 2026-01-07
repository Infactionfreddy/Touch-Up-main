//
//  Model.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 03.02.23.
//

import AppKit
import Combine
import TouchUpCore

class TouchUp: NSObject, ObservableObject {
    
    let touchManager: TUCTouchInputManager
    @Published var touches = [TUCTouch]()
    
    
    var observers = [AnyCancellable]()
    
    
    @Published var isPublishingMouseEventsEnabled = true
    
    @Published var connectionState: ConnectionState = .disconnected
    
    
    
    @Published var holdDuration: TimeInterval = 0.1
    @Published var doubleClickDistance: CGFloat = 3 //mm
    @Published var errorResistance: NSInteger = 0 // num of Reports to wait before cancelling a touch
    @Published var ignoreOriginTouches: Bool = false
    
    
    
    // Gesten deaktiviert - nur Klick und Ziehen aktiv
    @Published var isScrollingWithOneFingerEnabled = false
    @Published var isSecondaryClickEnabled = false
    @Published var isMagnificationEnabled = false
    @Published var isClickWindowToFrontEnabled = false
    @Published var isClickOnLiftEnabled = false
    
    
    
    @Published var connectedScreens = [TUCScreen]()
    var connectedTouchscreen: TUCScreen?
    
    var lastDateUSBAdded: Date?
    var lastDateScreenAdded: Date?
    var idOfLastAddedScreen: UInt?
    
    let hotPlugTimeInterval: TimeInterval = 10
    
    
    @Published var isAccessibilityAccessGranted = false
    
    // MARK: - Attempt to automatically determine touch screen
    
    
    
    var identificationCues: (name:String, id:UInt) {
        get {
            let name = UserDefaults.standard.string(forKey: "touchscreenNameCue") ?? "Digital"
            let id   = UserDefaults.standard.integer(forKey: "touchscreenIDCue")
            return (name, UInt(id))
        }
    }
    
    func rememeberCues() {
        if let connectedTouchscreen = self.touchscreen() {
            UserDefaults.standard.set(connectedTouchscreen.name, forKey: "touchscreenNameCue")
            UserDefaults.standard.set(connectedTouchscreen.id,   forKey: "touchscreenIDCue")
        }
    }
    
    
    /**
     returns true, if the screen list contained the preferred screen which is now assigned the touch screen.
     if screen list empty, it removes the assigned touch screen.
     */
    @discardableResult func identifyPreferredOrNoScreen() -> Bool {
        let cues = identificationCues
        print("[Prefer] Looking for screen matching name='\(cues.name)' id=\(cues.id)")
        
        
        if connectedScreens.count == 0 {
            self.connectedTouchscreen = nil
            self.connectionState = .uncertain
            print("OH NO SCREEN")
            return true
        }
        
       
        
        if let perfectMatch = connectedScreens.first(where: { 
            let matchScore = $0.matching(name: cues.name, id: cues.id)
            print("[Prefer]   \($0.name) ID=\($0.id) -> matchScore=\(matchScore)")
            return matchScore == 1
        }) {
            self.connectedTouchscreen = perfectMatch
            self.connectionState = lastDateUSBAdded == nil ? .connectedPreferred : .connectedHotPlug
            print("[Prefer] FOUND PREFERRED SCREEN: \(perfectMatch.name)")
            return true
        }
        
        print("[Prefer] NO perfect match found")
        return false
    }
    
    
    @discardableResult func identifyHotPlug() -> Bool {
        // if the USB cable of a touch screen was plugged in within last 10 seconds, assign this to the touchscreen
        
        // no need to hot plug during existing connection
        if self.connectionState.isConnected {
            print("HOTPLUG SKIPPED")
            return false
        }
        
        if let lastDateUSBAdded, let lastDateScreenAdded, let idOfLastAddedScreen {
            if Date().timeIntervalSince(lastDateUSBAdded) < hotPlugTimeInterval
                && Date().timeIntervalSince(lastDateScreenAdded) < hotPlugTimeInterval {
                
                
                if let screen = self.connectedScreens.first(where: {$0.id == idOfLastAddedScreen}) {
                    self.connectedTouchscreen = screen
                    let cues = identificationCues
                    let match = screen.matching(name: cues.name, id: cues.id)
                    self.connectionState = match == 1 ? .connectedPreferred : .connectedHotPlug
                    print("HOTPLUG SUCCESS")
                    return true
                }
                
                print("HOTPLUG FAIL")
            }
        }
        
        return false
    }
    
    
    @objc func screenParametersDidChange() {
        // identify which screen is newly added.
        let oldScreenList = self.connectedScreens
        self.connectedScreens = TUCScreen.allScreens() as! [TUCScreen]
        
        print("[Screen Debug] Available screens: \(self.connectedScreens.count)")
        for (i, screen) in self.connectedScreens.enumerated() {
            print("[Screen Debug]   [\(i)] \(screen.name) ID=\(screen.id) origin=(\(screen.frame.origin.x),\(screen.frame.origin.y))")
        }
        
        // a new screen appeared!
        if connectedScreens.count > oldScreenList.count {
            self.lastDateScreenAdded = Date()
            
            let new = connectedScreens.first { s in
                !(oldScreenList.contains(where: {$0.id == s.id}))
            }
            if let new {
                self.idOfLastAddedScreen = new.id
                identifyHotPlug()
            }
        }
        
        // search for the preferred screen, also important if user rearranged screens (and screen numbers)
        if !self.identifyPreferredOrNoScreen() {
            let mainID = CGMainDisplayID()

            // 1) Prefer a calibrated screen (likely the touch panel)
            let calibrated = self.connectedScreens.filter { $0.isCalibrated }
            if let bestCalibrated = calibrated.max(by: { ($0.frame.size.width * $0.frame.size.height) < ($1.frame.size.width * $1.frame.size.height) }) {
                self.connectedTouchscreen = bestCalibrated
                print("[Screen Selection] DEFAULT (CALIBRATED) screen selected: \(bestCalibrated.name) id=\(bestCalibrated.id)")
            }
            // 2) Else prefer external largest
            else if let bestExternal = self.connectedScreens.filter({ $0.id != mainID }).max(by: { ($0.frame.size.width * $0.frame.size.height) < ($1.frame.size.width * $1.frame.size.height) }) {
                self.connectedTouchscreen = bestExternal
                print("[Screen Selection] DEFAULT (EXTERNAL) screen selected: \(bestExternal.name) id=\(bestExternal.id)")
            }
            // 3) Else main
            else if let mainScreen = self.connectedScreens.first(where: { $0.id == mainID }) {
                self.connectedTouchscreen = mainScreen
                print("[Screen Selection] DEFAULT (MAIN) screen selected: \(mainScreen.name) id=\(mainScreen.id)")
            }
            // 4) Else last fallback
            else {
                self.connectedTouchscreen = self.connectedScreens.last
                print("[Screen Selection] DEFAULT (LAST) screen selected: \(self.connectedTouchscreen?.name ?? "NONE") id=\(self.connectedTouchscreen?.id ?? 0)")
            }
        } else {
            print("[Screen Selection] Using PREFERRED screen: \(self.connectedTouchscreen?.name ?? "NONE") id=\(self.connectedTouchscreen?.id ?? 0)")
        }
    }
    
    
    func checkAccessibilityAccessGranted() {
        // WICHTIG: kAXTrustedCheckOptionPrompt auf false setzen, um keine Dialog-Loop zu verursachen
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let isGranted = AXIsProcessTrustedWithOptions([checkOptPrompt: false] as CFDictionary?)
        
        // Synchron auf Main Thread schreiben statt async
        self.isAccessibilityAccessGranted = isGranted
        if isGranted {
            print("[AccessibilityCheck] ✅ Bedienungshilfen-Berechtigung AKTIV")
        } else {
            print("[AccessibilityCheck] ❌ Bedienungshilfen-Berechtigung FEHLT")
        }
    }
    
    func grantAccessibilityAccess() {
        print("[grantAccessibilityAccess] Öffne Systemeinstellungen...")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
            NSWorkspace.shared.open(url)
        }
        (NSApp.delegate as? AppDelegate)?.settingsWindow.close()
    }
    
    
    override init() {
        self.touchManager = TUCTouchInputManager()
        
        super.init()
        
        print("[TouchUp Init] STARTED")
        
        self.screenParametersDidChange()
        
        self.touchManager.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(TouchUp.screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        initPreferences()
        
        // FORCE enable postMouseEvents - das ist kritisch!
        print("[TouchUp Init] Erzwinge postMouseEvents=true")
        self.isPublishingMouseEventsEnabled = true
        self.touchManager.postMouseEvents = true
        
        checkAccessibilityAccessGranted()
        
        print("[TouchUp Init] DONE - postMouseEvents=\(self.touchManager.postMouseEvents)")
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
}


// MARK: - Loading, Saving and Syncing Settings with Framework
extension TouchUp {
    
    func initPreferences() {
        let defaults = UserDefaults.standard
        
        defaults.register(defaults: [
            "holdDuration" : 0.1,
            "doubleClickDistance" : 8,
            "errorResistance" : 4,
            "ignoreOriginTouches" : true,
            
            // WICHTIG: isPublishingMouseEventsEnabled startet immer auf TRUE
            "isPublishingMouseEventsEnabled" : true,
            "isScrollingWithOneFingerEnabled" : false,
            "isSecondaryClickEnabled" : false,
            "isMagnificationEnabled" : false,
            "isClickWindowToFrontEnabled" : false,
            "isClickOnLiftEnabled" : false
        ])
        
        holdDuration = defaults.double(forKey: "holdDuration")
        doubleClickDistance = defaults.double(forKey: "doubleClickDistance")
        errorResistance = defaults.integer(forKey: "errorResistance")
        ignoreOriginTouches = defaults.bool(forKey: "ignoreOriginTouches")
        
        // Lies die Einstellung, aber default ist TRUE
        let savedState = defaults.bool(forKey: "isPublishingMouseEventsEnabled")
        print("[initPreferences] isPublishingMouseEventsEnabled aus defaults = \(savedState)")
        isPublishingMouseEventsEnabled = true  // IMMER true, nicht aus defaults
        
        // Setup observers FIRST
        self.observers = [
            $isPublishingMouseEventsEnabled.assign(to: \.postMouseEvents, on: touchManager),
            $holdDuration.assign(to: \.holdDuration, on: touchManager),
            $doubleClickDistance.assign(to: \.doubleClickTolerance, on: touchManager),
            $errorResistance.assign(to: \.errorResistance, on: touchManager),
            $ignoreOriginTouches.assign(to: \.ignoreOriginTouches, on: touchManager),
            $isScrollingWithOneFingerEnabled.assign(to: \.isScrollingWithOneFingerEnabled, on: touchManager),
            $isSecondaryClickEnabled.assign(to: \.isSecondaryClickEnabled, on: touchManager),
            $isMagnificationEnabled.assign(to: \.isMagnificationEnabled, on: touchManager),
            $isClickWindowToFrontEnabled.assign(to: \.isClickWindowToFrontEnabled, on: touchManager),
            $isClickOnLiftEnabled.assign(to: \.isClickOnLiftEnabled, on: touchManager)
        ]
        
        // Then forcefully set the values AFTER observers to ensure correct state
        touchManager.postMouseEvents = true  // IMMER true!
        touchManager.holdDuration = holdDuration
        touchManager.doubleClickTolerance = doubleClickDistance
        touchManager.errorResistance = errorResistance
        touchManager.ignoreOriginTouches = ignoreOriginTouches
        
        isScrollingWithOneFingerEnabled = false  // Gesten deaktiviert
        isSecondaryClickEnabled = false
        isMagnificationEnabled = false
        isClickWindowToFrontEnabled = false
        isClickOnLiftEnabled = false
        
        // Set initial gesture values on touchManager
        touchManager.isScrollingWithOneFingerEnabled = isScrollingWithOneFingerEnabled
        touchManager.isSecondaryClickEnabled = isSecondaryClickEnabled
        touchManager.isMagnificationEnabled = isMagnificationEnabled
        touchManager.isClickWindowToFrontEnabled = isClickWindowToFrontEnabled
        touchManager.isClickOnLiftEnabled = isClickOnLiftEnabled
        
        print("[initPreferences] DONE - postMouseEvents=\(touchManager.postMouseEvents)")
    }
    
    
    func savePreferences() {
        let defaults = UserDefaults.standard
        
        defaults.set(holdDuration, forKey: "holdDuration")
        defaults.set(doubleClickDistance, forKey: "doubleClickDistance")
        defaults.set(errorResistance, forKey: "$errorResistance")
        defaults.set(ignoreOriginTouches, forKey: "ignoreOriginTouches")
        
        defaults.set(isScrollingWithOneFingerEnabled, forKey: "isScrollingWithOneFingerEnabled")
        defaults.set(isSecondaryClickEnabled, forKey: "isSecondaryClickEnabled")
        defaults.set(isMagnificationEnabled, forKey: "isMagnificationEnabled")
        defaults.set(isClickWindowToFrontEnabled, forKey: "isClickWindowToFrontEnabled")
        defaults.set(isClickOnLiftEnabled, forKey: "isClickOnLiftEnabled")
    }
    
}



extension TouchUp: TUCTouchDelegate {
    
    func touchesDidChange() {
        self.touches = self.touchManager.touchSet.allObjects as! [TUCTouch]
    }
    
    
    func touchscreen() -> TUCScreen? {
        self.connectedTouchscreen ?? self.connectedScreens.last
    }

    
    func action(for gesture: TUCCursorGesture) -> TUCCursorAction {
        switch gesture {
        case .TUCCursorGestureTouchDown:
            return isClickWindowToFrontEnabled ? .moveClickIfNeeded : .move
            
        case .TUCCursorGestureTap:
            return .click
            
        case .TUCCursorGestureLongPress:
            return .click
            
        case .TUCCursorGestureDrag:
            return isClickOnLiftEnabled ? .pointAndClick : (isScrollingWithOneFingerEnabled ? .scroll : .move)
            
        case .TUCCursorGestureHoldAndDrag:
            return .drag
            
        case .TUCCursorGestureTapSecondFinger:
            return isSecondaryClickEnabled ? .secondaryClick : .none
            
        case .TUCCursorGestureTwoFingerDrag:
            return isScrollingWithOneFingerEnabled ? .drag : .scroll
            
        case .TUCCursorGesturePinch:
            return isMagnificationEnabled ? .magnify : .none
            
        default:
            return .none
        }
    }
    
    
    
    func touchscreenDidConnect() {
        self.lastDateScreenAdded = Date()
        
        if !self.identifyHotPlug() {
            if self.connectionState.isConnected {
                self.connectionState = .uncertain
            }
        }
        
        self.identifyPreferredOrNoScreen()
    }
    
    func touchscreenDidDisconnect() {
        self.connectionState = .disconnected
    }
}


extension TouchUp {
    func uiLabels<T>(for keyPath: KeyPath<TouchUp, T>) -> (title:String, description:String) {
        switch keyPath {
        case \.isPublishingMouseEventsEnabled:
            return("Control Mouse with Touch",
                   "Turns the driver on or off.")
            
        case \.connectedTouchscreen:
            return("Assign Mouse Events to",
                   "Specifies which screen should receive the touch events.")
            
        case \.isScrollingWithOneFingerEnabled:
            return("Scroll with one finger",
                   "Scroll by dragging one finger over the touchscreen. If this option is disabled, you will move the cursor instead.")
            
        case \.isSecondaryClickEnabled:
            return("Secondary Click",
                   "While your pointing finger is resting on the screen, tap another finger in proximity to it to generate a secondary click event at the location of the first finger.")
            
        case \.isMagnificationEnabled:
            return("Magnification",
                   "Pinch two fingers to increase or decrease the size of the content. (EXPERIMENTAL)")
            
        case \.isClickWindowToFrontEnabled:
            return("Bring Windows to Front",
                   "When touching a window that is not frontmost, bring it to front first. (EXPERIMENTAL)")
            
        case \.isClickOnLiftEnabled:
            return("Point and click",
                   "Very reduced input set for exhibits: Move cursor by dragging, and click by releasing. Overrides scrolling and dragging functionality.")
            
        case \.holdDuration:
            return("Hold Duration",
                   "How long do you have to hold finger to initiate hold&drag")
            
        case \.doubleClickDistance:
            return("Double Click Zone",
                   "How many mm can two taps be apart from each other to qualify double click")
            
        case \.ignoreOriginTouches:
            return("Ignore Origin Touches",
                   "If your touchscreen randomly sends coordinate (0,0) in its datastream, toggle this option to make input more stable.")
            
        case \.errorResistance:
            return("Error Resistance",
                   "If your touchscreen is really unreliable at reporting touches, increase this slider to make inputs more stable at the cost of higher latency in detecting liftoffs.")
            
        default:
            return("\(keyPath)", "")
        }
    }
}


enum ConnectionState: Int {
    case uncertain
    case disconnected
    case connectedHotPlug // connected as result from hot plugging within a few seconds
    case connectedPreferred // connected with stored cues matching perfectly
    
    var image: NSImage? {
        let image: NSImage?
        
        switch self {
        case .uncertain:
            image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
        case .disconnected:
            image = NSImage(systemSymbolName: "rectangle.badge.xmark", accessibilityDescription: nil)
        default:
            image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: nil)
        }

        image?.isTemplate = true
        
        return image
    }
    
    var isConnected: Bool {
        return self == .connectedPreferred || self == .connectedHotPlug
    }
}
                 
                 
extension TUCScreen: Identifiable {
    func matching(name:String, id:UInt) -> Float {
        let sameName = self.name == name
        let sameID = self.id == id
        
        if sameName && sameID { return 1 }
        else if sameName { return 0.5 }
        else if sameID { return 0.2 }
        else { return 0}
    }
}
