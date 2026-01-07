//
//  SettingsView.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 03.02.23.
//

import SwiftUI
import TouchUpCore

struct SettingsView: View {
    
    @ObservedObject var model: TouchUp
    
    var welcomeBanner: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Touch Up 🐑")
                    .font(.largeTitle)
                Text("Touch Up converts USB HID data from any Windows certified touchscreen to mouse events.\nInjecting mouse events requires access to accessibility APIs. You can allow this by clicking the button below.")
            }
            
            HStack {
                Spacer()
                Button {
                    model.grantAccessibilityAccess()
                } label: {
                    
                    Text("Grant Accessibility Access")
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
    }
    
    var top: some View {
        Group {
            Toggle(model.uiLabels(for: \.isPublishingMouseEventsEnabled).title, isOn: $model.isPublishingMouseEventsEnabled)
            
            let id_: Binding<UInt> = Binding {return (model.connectedTouchscreen?.id) ?? 0}
            set: { value in
                model.connectedTouchscreen = model.connectedScreens.first(where:{$0.id == value})
                model.rememeberCues()
            }

            Picker(model.uiLabels(for: \.connectedTouchscreen).title, selection: id_) {
                ForEach(model.connectedScreens) {
                    Text($0.name).tag($0.id)
                }
            }
        }
    }
    
    
    var gestureSettings: some View {
        Group {
            // Gesten deaktiviert - nur Klick und Ziehen aktiv
            Text("Nur Klicken und Ziehen aktiv")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    
    var parameterSettings: some View {
        Group {
            Slider(value: $model.holdDuration, in: 0.0...0.16, step: 0.02){
                SettingsExplanationLabel(labels: model.uiLabels(for: \.holdDuration))
            }
            
            Slider(value: $model.doubleClickDistance, in: 0...8, step: 1) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.doubleClickDistance))
            }
        }
    }
    
    
    var troubleshootingSettings: some View {
        Group {
            let errorResistance_ = Binding {Double(model.errorResistance)} set: {
                model.errorResistance = NSInteger(Int($0)) }
            
            Slider(value: errorResistance_ , in: 0...10, step: 1) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.errorResistance))
            }
            
            Toggle(isOn: $model.ignoreOriginTouches) {
                SettingsExplanationLabel(labels: model.uiLabels(for: \.ignoreOriginTouches))
            }
            
            Divider()
            
            // ELAN Touchscreen specific settings
            VStack(alignment: .leading, spacing: 8) {
                Text("ELAN Touchscreen Support")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                
                Text("This version includes enhanced support for ELAN touchscreens (Vendor ID: 0x04F3). Check the console output for device detection information.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            
            Button(action: {
                (NSApp.delegate as? AppDelegate)?.showDebugOverlay()
            }, label: {
                HStack {
                    Text("Open Fullscreen Test Environment")
                    Spacer()
                    Image(systemName: "arrow.up.forward.app.fill")
                }
                
            })
            .foregroundColor(.accentColor)
            .buttonStyle(PlainButtonStyle())
            
            Divider()
            
            Button(action: {
                if let screen = model.connectedTouchscreen {
                    screen.startCalibration()
                    // Öffne Debug-Overlay für Kalibrierung
                    (NSApp.delegate as? AppDelegate)?.showDebugOverlay()
                    print("[SettingsView] Kalibrierung gestartet - fullscreen overlay öffnet")
                }
            }, label: {
                HStack {
                    Text("Start Touchscreen Calibration")
                    Spacer()
                    Image(systemName: "target")
                }
            })
            .foregroundColor(.accentColor)
            .buttonStyle(PlainButtonStyle())
            
            Text("Im Fullscreen Overlay tippe auf unten-links und dann oben-rechts in die Ecken.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
        }
    }
    
    
    var footer: some View {
        HStack {
            Spacer()
            VStack {
                if let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Touch Up v\(versionString)")
                        .font(.title2)
                }

                Text("Made with 🐑 in Aachen")
                    .font(.footnote)
                
                Link(destination: URL(string: "https://github.com/shueber/Touch-Up")!, label: {
                    Label("GitHub", systemImage: "link")
                        .foregroundColor(.accentColor)
                })
            }
            .padding(.vertical)
            Spacer()
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        
    }
    
    var container: some View {
        if #available(macOS 13.0, *) {
            return Form {
                if !model.isAccessibilityAccessGranted {
                    Section {
                        welcomeBanner
                    } footer: {
                        Rectangle()
                            .frame(width:0, height:0)
                            .foregroundColor(.clear)
                    }

                }
                
                Section {
                    top
                }

                Section("Gestures") {
                    gestureSettings
                }
                
                Section("Parameters") {
                    parameterSettings
                }

                Section {
                    troubleshootingSettings
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    footer
                }



            }
            .formStyle(.grouped)

        } else {
            return List {
                LegacySection {
                    top
                }
                
                LegacySection(title: "Gestures") {
                    gestureSettings
                }
                
                LegacySection(title: "Parameters") {
                    parameterSettings
                }
                
                LegacySection(title: "Troubleshooting") {
                    troubleshootingSettings
                }
                
                footer
                
            }
            .toggleStyle(.switch)
            
        }
    }
    
    
    
    var body: some View {
        container
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 350,  maxHeight: .infinity)
        
    }
}


struct LegacySection<Content: View>: View {
    var title: String? = nil
    var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading) {
            if let title = title {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 12)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .foregroundColor(.secondary.opacity(0.1))
                    .shadow(radius: 1)
                    
                    
                
                VStack(alignment: .leading, spacing: 16, content: content)
                    .padding(12)
            }
            
        }
        .padding(.bottom)
    }
}


struct SettingsExplanationLabel: View {
    
    let labels: (title:String, description:String)
    
    var body: some View {
        VStack(alignment:.leading, spacing: 4) {
            Text(labels.title)
            Text(labels.description)
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}



struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(model: TouchUp())
    }
}
