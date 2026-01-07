//
//  DebugView.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 11.02.23.
//

import SwiftUI
import AppKit
import TouchUpCore

struct DebugView: View {
    
    @ObservedObject var model: TouchUp
    
    let closeAction: ()->Void
    
    var pixelsPerMM: CGFloat
    
    @State private var calibrationPointsCaptured = 0
    @State private var lastProcessedTouchId: UUID? = nil
    @State private var lastTapTime: Date? = nil  // Debounce: Verhindere mehrfache Taps
    
    let tapDebounceInterval: TimeInterval = 0.5  // 500ms Wartezeit zwischen Taps
    
    init(model: TouchUp, closeAction: @escaping ()->Void) {
        self.model = model
        self.pixelsPerMM = model.touchscreen()?.pixelsPerMM() ?? 30
        self.closeAction = closeAction
    }
    
    func colorForPhase(_ phase: NSTouch.Phase) -> Color {
        switch phase {
        case .stationary:
            return Color.yellow
            
        case .began:
            return Color.blue
            
        case .ended:
            return Color.red
    
        case .cancelled:
            return Color.orange
            
        default:
            return Color.green
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            Rectangle()
                .foregroundColor(Color(white: 0.1))
                .frame(maxWidth:.infinity, maxHeight: .infinity)
                .overlay(GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        
                        // 4-PUNKT KALIBRIERUNGS-UI
                        if let screen = model.connectedTouchscreen, screen.isCalibrated == false {
                            VStack(spacing: 0) {
                                Text("4-PUNKT KALIBRIERUNG")
                                    .font(.system(size: 44, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.top, 40)
                                
                                Spacer()
                                    .frame(height: 30)
                                
                                // Status Text
                                VStack(spacing: 15) {
                                    let points = ["OBEN-LINKS", "OBEN-RECHTS", "UNTEN-LINKS", "UNTEN-RECHTS"]
                                    let nextText = points[min(calibrationPointsCaptured, 3)]
                                    
                                    Text("Punkt \(calibrationPointsCaptured + 1) von 4")
                                        .font(.system(size: 32, weight: .semibold))
                                        .foregroundColor(.cyan)
                                    
                                    Text("Tippe auf \(nextText)")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.green)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(height: 100)
                                .id(calibrationPointsCaptured)  // Force rebuild
                                
                                Spacer()
                                
                                // Visuelle Kalibrierungs-Punkte
                                ZStack {
                                    // Rahmen
                                    Rectangle()
                                        .stroke(Color.gray, lineWidth: 2)
                                        .foregroundColor(.clear)
                                    
                                    // 4 Punkte mit visuellen Targets
                                    let positions = [
                                        (name: "A", x: 0.0, y: 0.0, completed: calibrationPointsCaptured > 0),    // Oben-Links
                                        (name: "B", x: 1.0, y: 0.0, completed: calibrationPointsCaptured > 1),    // Oben-Rechts
                                        (name: "C", x: 0.0, y: 1.0, completed: calibrationPointsCaptured > 2),    // Unten-Links
                                        (name: "D", x: 1.0, y: 1.0, completed: calibrationPointsCaptured > 3)     // Unten-Rechts
                                    ]
                                    
                                    ForEach(0..<4, id: \.self) { index in
                                        let pos = positions[index]
                                        let isActive = index == calibrationPointsCaptured  // Dieser Punkt wird gerade kalibriert
                                        let isCompleted = pos.completed
                                        
                                        VStack(spacing: 8) {
                                            // Visuelle Target
                                            Circle()
                                                .stroke(isActive ? Color.yellow : (isCompleted ? Color.green : Color.gray), lineWidth: isActive ? 4 : 2)
                                                .frame(width: 120, height: 120)
                                            
                                            // Innerer Kreis
                                            Circle()
                                                .fill(isActive ? Color.yellow.opacity(0.3) : (isCompleted ? Color.green.opacity(0.3) : Color.gray.opacity(0.1)))
                                                .frame(width: 80, height: 80)
                                            
                                            // Punkt-Label
                                            Text(pos.name)
                                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                                .foregroundColor(isActive ? .yellow : (isCompleted ? .green : .gray))
                                            
                                            // Status-Icon
                                            if isCompleted {
                                                Text("✓")
                                                    .font(.system(size: 28, weight: .bold))
                                                    .foregroundColor(.green)
                                            } else if isActive {
                                                Text("→")
                                                    .font(.system(size: 28, weight: .bold))
                                                    .foregroundColor(.yellow)
                                                    .opacity(0.6)
                                            }
                                        }
                                        .position(
                                            x: geo.size.width * CGFloat(pos.x),
                                            y: geo.size.height * 0.5 + (geo.size.height * 0.35 * CGFloat(pos.y))
                                        )
                                    }
                                    
                                    // Touch-Punkte anzeigen
                                    ForEach(model.touches, id:\.uuid) { point in
                                        Circle()
                                            .foregroundColor(colorForPhase(point.phase))
                                            .border(Color.cyan, width: 2)
                                            .opacity(point.isActive() ? 0.8 : 0.3)
                                            .frame(width: 16 * pixelsPerMM, height: 16 * pixelsPerMM)
                                            .position(x: geo.size.width * point.location.x,
                                                      y: geo.size.height * point.location.y)
                                    }
                                }
                                .frame(height: geo.size.height * 0.5)
                                .padding(.horizontal, 40)
                                .padding(.bottom, 40)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.85))
                        } else {
                            // Normal mode: Zeige Touch-Punkte
                            ForEach(model.touches, id:\.uuid) { point in
                                Circle()
                                    .foregroundColor(colorForPhase(point.phase))
                                    .border(Color.gray, width: point.confidenceFlag ? 5: 0)
                                    .opacity(point.isActive() ? 1 : 0.5)
                                    .frame(width: 16 * pixelsPerMM, height: 16 * pixelsPerMM)
                                    .position(x: geo.size.width * point.location.x,
                                              y: geo.size.height * point.location.y)
                                
                                Text("\(point.contactID)")
                                    .font(.system(size: 40))
                                    .position(x: geo.size.width * point.location.x,
                                              y: geo.size.height * point.location.y)
                            }
                        }
                    }
                })
                .onReceive(model.$touches) { touches in
                    print("[DebugView.onReceive] touches changed, count=\(touches.count)")
                    
                    // Erkenne Kalibrierungs-Taps - Akzeptiere .began oder neue UUID
                    if let screen = model.connectedTouchscreen, screen.isCalibrated == false {
                        print("[DebugView.onReceive] Kalibrierungsmodus aktiv, calibrationPointsCaptured=\(calibrationPointsCaptured)")
                        
                        // Debounce: Überprüfe ob genug Zeit seit letztem Tap vergangen ist
                        let now = Date()
                        let timeSinceLastTap = lastTapTime.map { now.timeIntervalSince($0) } ?? Double.infinity
                        let isDebounceExpired = timeSinceLastTap >= tapDebounceInterval
                        
                        if !isDebounceExpired {
                            print("[DebugView] IGNORIERT - Debounce aktiv (\(String(format: "%.0f", timeSinceLastTap * 1000))ms seit letztem Tap)")
                        }
                        
                        for touch in touches {
                            let phaseStr = touch.phase == .ended ? "ENDED" : touch.phase == .began ? "BEGAN" : touch.phase == .moved ? "MOVED" : "STATIONARY"
                            print("[DebugView.onReceive] Touch: phase=\(phaseStr), contactID=\(touch.contactID), uuid=\(touch.uuid.uuidString.prefix(8)), location=(\(String(format: "%.2f", touch.location.x)), \(String(format: "%.2f", touch.location.y)))")
                            
                            // Erkenne Taps wenn:
                            // 1. Debounce ist abgelaufen UND
                            // 2. Phase == .began ODER neue UUID
                            let isNewTap = (touch.phase == .began) || (lastProcessedTouchId != touch.uuid && touch.isActive())
                            
                            if isNewTap && isDebounceExpired {
                                print("[DebugView] >>>>>> TAP ERKANNT (phase=\(phaseStr), neue UUID oder BEGAN) <<<<<<")
                                
                                // KRITISCH: Verwende die TATSÄCHLICHE Cursor-Position in CGDisplay-Koordinaten!
                                // CGEvent.location gibt direkt CGDisplay-Koordinaten (origin unten-links, global)
                                // Das ist genau das Format, das TUCScreen für Kalibrierung erwartet
                                let mouseLocation = CGEvent(source: nil)?.location ?? CGPoint.zero
                                let screenPoint = CGPoint(x: mouseLocation.x, y: mouseLocation.y)
                                
                                // Prüfe ob der Cursor auf dem RICHTIGEN Display ist
                                let screenFrame = CGRect(x: screen.frame.origin.x, 
                                                        y: screen.frame.origin.y,
                                                        width: screen.frame.size.width,
                                                        height: screen.frame.size.height)
                                let isOnCorrectScreen = screenFrame.contains(screenPoint)
                                
                                print("[DebugView] Kalibrierung auf Screen '\(screen.name)' (ID=\(screen.id)): touchPos=(\(String(format: "%.2f", touch.location.x)), \(String(format: "%.2f", touch.location.y))) -> ACTUAL cursorPos=(\(String(format: "%.0f", screenPoint.x)), \(String(format: "%.0f", screenPoint.y))) onCorrectScreen=\(isOnCorrectScreen)")
                                
                                if !isOnCorrectScreen {
                                    print("[DebugView] ⚠️  FEHLER: Cursor ist NICHT auf Display '\(screen.name)'! Frame=\(screenFrame)")
                                    print("[DebugView] ⚠️  Bitte tippe auf das EXTERNE Display, nicht auf das Built-in Display!")
                                    // Ignoriere diesen Tap
                                    break
                                }
                                
                                if calibrationPointsCaptured == 0 {
                                    print("[DebugView] SPEICHERE PUNKT A - recordCalibrationPoint aufgerufen")
                                    screen.recordCalibrationPoint(touch.location, atScreenLocation: screenPoint, pointIndex: 0)
                                    DispatchQueue.main.async {
                                        self.calibrationPointsCaptured = 1
                                        self.lastProcessedTouchId = nil
                                        self.lastTapTime = Date()  // Setze Debounce-Zeit
                                        print("[DebugView] State aktualisiert zu: \(self.calibrationPointsCaptured), Debounce-Timer gestartet")
                                    }
                                } else if calibrationPointsCaptured == 1 {
                                    print("[DebugView] SPEICHERE PUNKT B - recordCalibrationPoint aufgerufen")
                                    screen.recordCalibrationPoint(touch.location, atScreenLocation: screenPoint, pointIndex: 1)
                                    DispatchQueue.main.async {
                                        self.calibrationPointsCaptured = 2
                                        self.lastProcessedTouchId = nil
                                        self.lastTapTime = Date()  // Setze Debounce-Zeit
                                        print("[DebugView] State aktualisiert zu: \(self.calibrationPointsCaptured) - KALIBRIERUNG FERTIG")
                                    }
                                }
                                
                                lastProcessedTouchId = touch.uuid
                                break
                            } else if isNewTap && !isDebounceExpired {
                                print("[DebugView] TAP IGNORIERT - Debounce noch aktiv")
                            }
                        }
                    }
                }
            
            Button(action: {
                closeAction()
            }, label: {
                HStack {
                    Text("Close overlay with ")
                    Label("W", systemImage: "command.square.fill")
                    Text("or by mouse-clicking here")
                }
                .font(.largeTitle)
                .modify {
                    if #available(macOS 13.0, *) {
                        $0.fontDesign(.rounded)
                    } else { $0 }
                }
            })
            .foregroundColor(.gray)
            .buttonStyle(.borderless)
            .keyboardShortcut(KeyEquivalent("w"), modifiers: [.command])
            .padding(.bottom, 140)
        }
    }
}

struct DebugView_Previews: PreviewProvider {
    static var previews: some View {
        DebugView(model: TouchUp(), closeAction: {})
    }
}

extension View {
    func modify<T: View>(@ViewBuilder _ modifier: (Self) -> T) -> some View {
        return modifier(self)
    }
}
