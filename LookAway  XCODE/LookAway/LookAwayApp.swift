import SwiftUI
import AppKit
import UserNotifications
import Combine
import ServiceManagement

// MARK: - App Entry Point
@main
struct LookAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Custom Window for Keyboard Input
class KeyInputWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?
    var breakWindow: NSWindow?
    var statusItem: NSStatusItem!
    let timerManager = TimerManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "eye", accessibilityDescription: "LookAway") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "👁️"
            }
            button.action = #selector(toggleSettings)
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in }
        
        timerManager.onBreakTime = { [weak self] breakMinutes in
            self?.showBreakScreen(duration: breakMinutes)
        }
        
        toggleSettings()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsWindow?.isVisible == false || settingsWindow == nil {
            toggleSettings()
        }
        return true
    }
    
    @objc func toggleSettings() {
        if settingsWindow == nil {
            let view = SettingsView(timerManager: timerManager)
            let hostingController = NSHostingController(rootView: view)
            
            settingsWindow = KeyInputWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 600),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.contentViewController = hostingController
            settingsWindow?.backgroundColor = .clear
            settingsWindow?.isOpaque = false
            settingsWindow?.hasShadow = true
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.level = .floating
        }
        
        if settingsWindow?.isVisible == true {
            settingsWindow?.orderOut(nil)
        } else {
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func showBreakScreen(duration: Int) {
        DispatchQueue.main.async {
            self.settingsWindow?.orderOut(nil)
            
            let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            
            if self.breakWindow == nil {
                self.breakWindow = KeyInputWindow(
                    contentRect: screenRect,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                self.breakWindow?.level = .screenSaver
                self.breakWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                self.breakWindow?.backgroundColor = .black
                self.breakWindow?.isOpaque = true
            }
            
            let breakView = BreakView(breakMinutes: duration) { [weak self] in
                self?.breakWindow?.orderOut(nil)
                self?.timerManager.resetTimer()
            }
            
            self.breakWindow?.contentView = NSHostingView(rootView: breakView)
            self.breakWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Timer Logic
class TimerManager: ObservableObject {
    @AppStorage("workMinutes") var workMinutes: Int = 60 {
        didSet { resetTimer() }
    }
    @AppStorage("breakMinutes") var breakMinutes: Int = 2
    
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { updateLoginItem() }
    }
    
    @Published var timeRemaining: Int
    @Published var isRunning: Bool = true
    
    private var timer: Timer?
    private var lastCheckTime: Date = Date()
    private var targetDate: Date = Date()
    private var warningShown = false
    
    var onBreakTime: ((Int) -> Void)?
    
    init() {
        self.timeRemaining = 60 * 60
        setupWorkspaceObservers()
        resetTimer()
        updateLoginItem()
    }
    
    func updateLoginItem() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to change login item status: \(error)")
        }
    }
    
    private func setupWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(macDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(macWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }
    
    @objc private func macWillSleep() {
        timer?.invalidate()
    }
    
    @objc private func macDidWake() {
        resetTimer()
    }
    
    func resetTimer() {
        timer?.invalidate()
        warningShown = false
        targetDate = Date().addingTimeInterval(TimeInterval(workMinutes * 60))
        updateTimeRemaining()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    func togglePause() {
        isRunning.toggle()
        if isRunning {
            targetDate = Date().addingTimeInterval(TimeInterval(timeRemaining))
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else {
            timer?.invalidate()
        }
    }
    
    private func tick() {
        guard isRunning else { return }
        updateTimeRemaining()
        
        let now = Date()
        if now.timeIntervalSince(lastCheckTime) > 12 {
            targetDate = now.addingTimeInterval(TimeInterval(workMinutes * 60))
            updateTimeRemaining()
        }
        lastCheckTime = now
        
        if timeRemaining == 15 && !warningShown {
            sendWarningNotification()
            warningShown = true
        }
        
        if timeRemaining <= 0 {
            timer?.invalidate()
            onBreakTime?(breakMinutes)
        }
    }
    
    private func updateTimeRemaining() {
        let diff = Int(targetDate.timeIntervalSinceNow)
        timeRemaining = max(0, diff)
    }
    
    private func sendWarningNotification() {
        let content = UNMutableNotificationContent()
        content.title = "LookAway"
        content.subtitle = "Time for a peaceful break in 15s"
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func timeString() -> String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Settings UI
struct SettingsView: View {
    @ObservedObject var timerManager: TimerManager
    @State private var phase: Double = 0.0
    
    var body: some View {
        ZStack {
            ProBackground(phase: $phase)
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: {
                        NSApp.delegate?.perform(#selector(AppDelegate.toggleSettings))
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(20)
                
                VStack(spacing: 8) {
                    Text("LOOK AWAY")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(Color(white: 0.5))
                        .tracking(8)
                    
                    Text("Workflow Preferences")
                        .font(.system(size: 24, weight: .medium, design: .default))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 40)
                
                VStack(spacing: 0) {
                    SettingRow(title: "Focus Time", value: $timerManager.workMinutes, range: 1...120, suffix: "min", onChangeAction: {
                        timerManager.resetTimer()
                    })
                    .padding(24)
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    SettingRow(title: "Break Time", value: $timerManager.breakMinutes, range: 1...30, suffix: "min")
                        .padding(24)
                }
                .background(Color(white: 0.08).opacity(0.7))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 30)
                
                Spacer()
                
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT BREAK IN")
                            .font(.system(size: 11, weight: .bold, design: .default))
                            .foregroundColor(Color(white: 0.4))
                        
                        Text(timerManager.timeString())
                            .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        timerManager.togglePause()
                    }) {
                        Image(systemName: timerManager.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
                
                Divider().background(Color.white.opacity(0.1))
                
                HStack {
                    Toggle("Launch at Login", isOn: $timerManager.launchAtLogin)
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                    
                    Spacer()
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Text("Quit")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(25)
            }
        }
        .frame(width: 450, height: 600)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .gesture(DragGesture().onChanged { _ in
            NSApp.mainWindow?.performDrag(with: NSApp.currentEvent!)
        })
    }
}

// MARK: - Setting Row
struct SettingRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String
    var onChangeAction: (() -> Void)? = nil
    
    @State private var stringValue: String = ""
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    if value > range.lowerBound {
                        value -= 1
                        onChangeAction?()
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 28, height: 28)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 2) {
                    TextField("", text: $stringValue)
                        .textFieldStyle(PlainTextFieldStyle())
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 50)
                        .onChange(of: stringValue) { oldValue, newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                stringValue = filtered
                            }
                            if let intValue = Int(filtered), range.contains(intValue) {
                                if value != intValue {
                                    value = intValue
                                    onChangeAction?()
                                }
                            }
                        }
                        .onSubmit {
                            if let intValue = Int(stringValue) {
                                let clamped = min(max(intValue, range.lowerBound), range.upperBound)
                                if value != clamped {
                                    value = clamped
                                    onChangeAction?()
                                }
                            }
                            stringValue = String(value)
                        }
                    
                    Text(suffix)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(white: 0.12))
                .cornerRadius(8)
                
                Button(action: {
                    if value < range.upperBound {
                        value += 1
                        onChangeAction?()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 28, height: 28)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .onAppear {
            stringValue = String(value)
        }
        .onChange(of: value) { oldValue, newValue in
            stringValue = String(newValue)
        }
    }
}

// MARK: - Break UI
struct BreakView: View {
    let breakMinutes: Int
    var onDismiss: () -> Void
    
    @State private var timeRemaining: Int
    @State private var phase: Double = 0.0
    
    init(breakMinutes: Int, onDismiss: @escaping () -> Void) {
        self.breakMinutes = breakMinutes
        self.onDismiss = onDismiss
        _timeRemaining = State(initialValue: breakMinutes * 60)
    }
    
    var body: some View {
        ZStack {
            ProBackground(phase: $phase)
            
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("LOOK AWAY")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(Color(white: 0.5))
                        .tracking(10)
                    
                    Text("Take a moment to breathe and rest.")
                        .font(.system(size: 52, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .lineSpacing(2)
                        .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 10)
                    
                    Text("Step away from the screen, clear your mind, and we will return to work refreshed shortly.")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(Color(white: 0.6))
                        .frame(width: 500, alignment: .leading)
                        .lineSpacing(6)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 30) {
                    Text(timeString(time: timeRemaining))
                        .font(.system(size: 150, weight: .thin, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
                        .fixedSize()
                    
                    Button(action: {
                        onDismiss()
                    }) {
                        Text("Return to work (ESC)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.8))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.15))
                            .cornerRadius(30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 30)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 120)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    timer.invalidate()
                    onDismiss()
                }
            }
            
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    onDismiss()
                    return nil
                }
                return event
            }
        }
    }
    
    func timeString(time: Int) -> String {
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Pro Background
struct ProBackground: View {
    @Binding var phase: Double
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [Color(red: 0.15, green: 0.2, blue: 0.35).opacity(0.5), .clear]),
                center: UnitPoint(x: 0.5 + sin(phase) * 0.4, y: 0.5 + cos(phase) * 0.4),
                startRadius: 0,
                endRadius: 900
            )
            .ignoresSafeArea()
            .blendMode(.screen)
        }
        .onAppear {
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Previews
#Preview {
    SettingsView(timerManager: TimerManager())
}
