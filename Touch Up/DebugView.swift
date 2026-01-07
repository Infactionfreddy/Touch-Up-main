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
    @State private var lastTapTime: Date? = nil
    
    let tapDebounceInterval: TimeInterval = 0.5
    
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
                        
                        // 4-PUNKT KALIBRIERUNGS-UI - PROFESSIONELLES DESIGN
                        if let screen = model.connectedTouchscreen, screen.isCalibrated == false {
                            ZStack(alignment: .center) {
                                // Dunkler Gradient-Hintergrund
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.95),
                                        Color(red: 0.1, green: 0.1, blue: 0.15).opacity(0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .ignoresSafeArea()
                                
                                // Zentraler Informations-Container
                                VStack(spacing: 30) {
                                    // Titel
                                    Text("TOUCHSCREEN KALIBRIERUNG")
                                        .font(.system(size: 38, weight: .bold, design: .default))
                                        .foregroundColor(.white)
                                        .tracking(1.5)
                                    
                                    // Progress Bar
                                    VStack(spacing: 12) {
                                        HStack {
                                            Text("Fortschritt")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.gray)
                                            
                                            Spacer()
                                            
                                            Text("\(calibrationPointsCaptured)/4")
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundColor(.cyan)
                                        }
                                        
                                        // Fortschrittsbalken
                                        GeometryReader { progressGeo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.gray.opacity(0.3))
                                                
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(
                                                        LinearGradient(
                                                            gradient: Gradient(colors: [Color.cyan, Color.blue]),
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: progressGeo.size.width * CGFloat(calibrationPointsCaptured) / 4)
                                            }
                                        }
                                        .frame(height: 6)
                                    }
                                    .frame(height: 60)
                                    
                                    // Aktuelle Anweisung
                                    VStack(spacing: 8) {
                                        let points = ["OBEN-LINKS", "OBEN-RECHTS", "UNTEN-LINKS", "UNTEN-RECHTS"]
                                        let nextText = points[min(calibrationPointsCaptured, 3)]
                                        
                                        Text("Tippe auf:")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.gray)
                                        
                                        Text(nextText)
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(.cyan)
                                            .tracking(0.5)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.05))
                                            .border(Color.cyan.opacity(0.3), width: 1)
                                    )
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(40)
                                
                                // 4 Kalibrierungs-Punkte an den Ecken
                                let positions = [
                                    (name: "1", x: 0.05, y: 0.05, label: "TOP-LEFT", completed: calibrationPointsCaptured > 0),
                                    (name: "2", x: 0.95, y: 0.05, label: "TOP-RIGHT", completed: calibrationPointsCaptured > 1),
                                    (name: "3", x: 0.05, y: 0.95, label: "BOTTOM-LEFT", completed: calibrationPointsCaptured > 2),
                                    (name: "4", x: 0.95, y: 0.95, label: "BOTTOM-RIGHT", completed: calibrationPointsCaptured > 3)
                                ]
                                
                                ForEach(0..<4, id: \.self) { index in
                                    let pos = positions[index]
                                    let isActive = index == calibrationPointsCaptured
                                    let isCompleted = pos.completed
                                    
                                    VStack(spacing: 4) {
                                        ZStack {
                                            // Äußerer Kreis (Puls-Effekt wenn aktiv)
                                            Circle()
                                                .stroke(
                                                    isActive ? Color.cyan : (isCompleted ? Color.green : Color.gray.opacity(0.3)),
                                                    lineWidth: 3
                                                )
                                                .frame(width: 100, height: 100)
                                                .scaleEffect(isActive ? 1.0 : 0.9)
                                                .opacity(isActive ? 1.0 : 0.7)
                                            
                                            // Mittlerer Kreis
                                            Circle()
                                                .stroke(
                                                    isActive ? Color.cyan : (isCompleted ? Color.green : Color.gray.opacity(0.2)),
                                                    lineWidth: 2
                                                )
                                                .frame(width: 70, height: 70)
                                                .opacity(isActive ? 1.0 : 0.5)
                                            
                                            // Innerer Punkt
                                            Circle()
                                                .fill(isActive ? Color.cyan : (isCompleted ? Color.green : Color.gray.opacity(0.3)))
                                                .frame(width: 40, height: 40)
                                            
                                            // Nummer
                                            Text(pos.name)
                                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                                .foregroundColor(isActive ? Color.black : Color.white)
                                        }
                                        
                                        // Status Indikator
                                        if isCompleted {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.green)
                                        } else if isActive {
                                            Image(systemName: "arrowtriangle.right.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.cyan)
                                                .offset(y: -2)
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    .position(
                                        x: geo.size.width * CGFloat(pos.x),
                                        y: geo.size.height * CGFloat(pos.y)
                                    )
                                }
                                
                                // Touch-Punkte visualisieren
                                ForEach(model.touches, id:\.uuid) { point in
                                    Circle()
                                        .foregroundColor(colorForPhase(point.phase))
                                        .border(Color.cyan, width: 1)
                                        .opacity(point.isActive() ? 0.6 : 0.2)
                                        .frame(width: 12 * pixelsPerMM, height: 12 * pixelsPerMM)
                                        .position(x: geo.size.width * point.location.x,
                                                  y: geo.size.height * point.location.y)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
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
                    if let screen = model.connectedTouchscreen, screen.isCalibrated == false {
                        let now = Date()
                        let timeSinceLastTap = lastTapTime.map { now.timeIntervalSince($0) } ?? Double.infinity
                        let isDebounceExpired = timeSinceLastTap >= tapDebounceInterval
                        
                        for touch in touches {
                            let isNewTap = (touch.phase == .began) || (lastProcessedTouchId != touch.uuid && touch.isActive())
                            
                            if isNewTap && isDebounceExpired && calibrationPointsCaptured < 4 {
                                // FIXED: Berechne Screen-Koordinaten aus der VISUELLEN Position des Kalibrierungsziels
                                // statt aus der (durch Fallback verfälschten) Cursor-Position
                                let calibrationTargets: [(CGFloat, CGFloat)] = [
                                    (0.05, 0.05),  // A: oben-links
                                    (0.95, 0.05),  // B: oben-rechts
                                    (0.05, 0.95),  // C: unten-links
                                    (0.95, 0.95)   // D: unten-rechts
                                ]
                                
                                let target = calibrationTargets[calibrationPointsCaptured]
                                let screenPoint = CGPoint(
                                    x: screen.frame.origin.x + target.0 * screen.frame.size.width,
                                    y: screen.frame.origin.y + target.1 * screen.frame.size.height
                                )
                                
                                print("[DebugView] PUNKT \(calibrationPointsCaptured + 1)/4: touch=(\(String(format: "%.2f", touch.location.x)), \(String(format: "%.2f", touch.location.y))) -> target=(\(String(format: "%.0f", screenPoint.x)), \(String(format: "%.0f", screenPoint.y)))")
                                screen.recordCalibrationPoint(touch.location, atScreenLocation: screenPoint, pointIndex: calibrationPointsCaptured)
                                
                                DispatchQueue.main.async {
                                    self.calibrationPointsCaptured += 1
                                    self.lastProcessedTouchId = nil
                                    self.lastTapTime = Date()
                                    
                                    if self.calibrationPointsCaptured >= 4 {
                                        print("[DebugView] ✅ ALLE 4 PUNKTE ERFASST!")
                                        // Warte 2 Sekunden damit die Kalibrierung vollständig abgeschlossen ist
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            print("[DebugView] Schließe UI...")
                                            self.closeAction()
                                        }
                                    }
                                }
                                
                                lastProcessedTouchId = touch.uuid
                                break
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
