import AppKit
import SwiftUI
import PomodoroCore

struct ScreenLayout {
    let screen: NSScreen
    let width: CGFloat
    let notchWidth: CGFloat
    let headerHeight: CGFloat
    var hasNotch: Bool { notchWidth > 0 }

    static func current() -> ScreenLayout {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 0 }
        return ScreenLayout(screen: screen, width: notchWidth > 0 ? notchWidth + 180 : 320,
                            notchWidth: notchWidth, headerHeight: notchWidth > 0 ? screen.safeAreaInsets.top : 34)
    }

    func bodyHeight(expansion: CGFloat) -> CGFloat { 140 * expansion }
    func height(expansion: CGFloat) -> CGFloat { headerHeight + bodyHeight(expansion: expansion) }
    func frame(expansion: CGFloat) -> NSRect {
        let height = height(expansion: expansion)
        let top = hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - 8
        return NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor fileprivate final class OverlayPresentation: ObservableObject {
    @Published var expansion: CGFloat
    init(expanded: Bool) { expansion = expanded ? 1 : 0 }
}

// One AppKit clock drives both the real window frame and the content fade.
// Reversing starts from the currently visible geometry, including mid-transition.
private final class PanelTransition: NSAnimation {
    var apply: ((CGFloat) -> Void)?
    override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set {
            super.currentProgress = newValue
            apply?(CGFloat(currentValue))
        }
    }
}

@MainActor final class OverlayController {
    private let model: TimerModel
    private let panel: NotchPanel
    private let presentation: OverlayPresentation
    private var layout = ScreenLayout.current()
    private var transition: PanelTransition?
    private var wantsKeyboardFocus = false

    init(model: TimerModel) {
        self.model = model
        presentation = OverlayPresentation(expanded: model.expanded)
        panel = NotchPanel(contentRect: layout.frame(expansion: presentation.expansion),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Pomodoro Notch"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstClickHostingView(rootView: OverlayView(model: model, layout: layout, presentation: presentation))
        model.onGeometryChange = { [weak self] in self?.update() }
        model.onKeyboardFocusRequest = { [weak self] in self?.requestKeyboardFocus() }
        model.onPresentationStatus = { [weak self] in
            guard let self else { return [:] }
            return ["height": self.panel.frame.height, "headerHeight": self.layout.headerHeight,
                    "top": self.panel.frame.maxY,
                    "expansion": self.presentation.expansion, "keyWindow": self.panel.isKeyWindow,
                    "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }
        update(animated: false)
    }

    func updateScreen() {
        layout = .current()
        (panel.contentView as? FirstClickHostingView<OverlayView>)?.rootView = OverlayView(model: model, layout: layout, presentation: presentation)
        update(animated: false)
    }

    func update(animated: Bool = true) {
        transition?.stop()
        transition = nil
        guard model.isVisible else {
            wantsKeyboardFocus = false
            panel.orderOut(nil)
            return
        }
        if !model.expanded {
            wantsKeyboardFocus = false
            if panel.isKeyWindow { panel.resignKey() }
        }
        let target: CGFloat = model.expanded ? 1 : 0
        let start = presentation.expansion
        panel.orderFrontRegardless()
        guard animated, abs(start - target) > 0.001,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            applyExpansion(target)
            completeKeyboardFocus()
            return
        }
        let animation = PanelTransition(duration: 0.18 * Double(abs(target - start)), animationCurve: .easeInOut)
        animation.animationBlockingMode = .nonblocking
        animation.frameRate = 60
        animation.apply = { [weak self] progress in
            guard let self else { return }
            self.applyExpansion(start + (target - start) * progress)
            if progress >= 1 {
                self.transition = nil
                self.completeKeyboardFocus()
            }
        }
        transition = animation
        animation.start()
    }

    private func applyExpansion(_ value: CGFloat) {
        presentation.expansion = value
        panel.setFrame(layout.frame(expansion: value), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func requestKeyboardFocus() {
        guard !CommandLine.arguments.contains("--no-focus") else { return }
        wantsKeyboardFocus = true
        if transition == nil { completeKeyboardFocus() }
    }

    private func completeKeyboardFocus() {
        guard wantsKeyboardFocus, model.isVisible, model.expanded else { return }
        wantsKeyboardFocus = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.keyboardFocusRequest += 1
    }
}

private struct TransportButtonStyle: ButtonStyle {
    let running: Bool
    let diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        TransportButtonContent(configuration: configuration, running: running, diameter: diameter)
    }
}

private struct TransportButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let running: Bool
    let diameter: CGFloat
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .background {
                Circle().fill(running
                              ? Color.white.opacity(hovered ? 0.09 : 0)
                              : Color(red: hovered ? 0.12 : 0.09, green: hovered ? 0.34 : 0.25, blue: hovered ? 0.19 : 0.14))
                    .frame(width: diameter, height: diameter)
            }
            .overlay {
                Circle().strokeBorder(running ? Color(red: 1, green: 0.62, blue: 0.20) : .clear, lineWidth: 2)
                    .frame(width: diameter, height: diameter)
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .animation(configuration.isPressed || reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    var restingOpacity = 0.7

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonContent(configuration: configuration, restingOpacity: restingOpacity)
    }
}

private struct QuietButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let restingOpacity: Double
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .foregroundStyle(.white.opacity(hovered ? 1 : restingOpacity))
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : hovered ? 0.07 : 0))
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .animation(configuration.isPressed || reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OverlayView: View {
    @ObservedObject var model: TimerModel
    let layout: ScreenLayout
    @ObservedObject fileprivate var presentation: OverlayPresentation
    @FocusState private var focusedControl: Control?
    @State private var editingTask = false
    @State private var taskInput = ""
    @State private var taskEditID = UUID()
    @State private var editingDuration = false
    @State private var durationInput = "25:00"
    @State private var durationEditID = UUID()
    private let controlColumnWidth: CGFloat = 52
    private let trailingInset: CGFloat = 16
    private enum Control: Hashable { case transport, compactTransport, primary, collapse, duration }
    private var orange: Color { Color(red: 1, green: 0.62, blue: 0.20) }
    private var green: Color { Color(red: 0.20, green: 0.83, blue: 0.36) }
    private var phaseName: String { model.isBreak ? "Break" : "Focus" }
    private var taskTitle: String { model.session.phase == .idle ? model.draft : model.session.task }
    private var remainingDescription: String {
        let seconds = Int(ceil(model.secondsLeft))
        return "\(seconds / 60) minutes, \(seconds % 60) seconds remaining"
    }
    private var transportLabel: String {
        if model.isActive {
            return "\(model.session.phase == .paused ? "Resume" : "Pause") \(model.isBreak ? "break" : "focus") timer"
        }
        return model.session.phase == .completed && !model.isBreak ? "Start 5-minute break" : "Start focus timer (\(model.focusClock))"
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            expandedContent
                .opacity(max(0, (presentation.expansion - 0.3) / 0.7))
                .allowsHitTesting(model.expanded && presentation.expansion > 0.99)
                .accessibilityHidden(!model.expanded)
                .frame(height: layout.bodyHeight(expansion: presentation.expansion), alignment: .top)
                .clipped()
        }
        .frame(width: layout.width, height: layout.height(expansion: presentation.expansion), alignment: .top)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: layout.hasNotch ? 0 : 18,
                                         bottomLeadingRadius: 22, bottomTrailingRadius: 22,
                                         topTrailingRadius: layout.hasNotch ? 0 : 18))
        .foregroundStyle(.white)
        .focusEffectDisabled()
        .environment(\.colorScheme, .dark)
        .onChange(of: model.keyboardFocusRequest) { _, _ in
            if !editingTask && !editingDuration { focusedControl = model.isActive ? .transport : .primary }
        }
        .onChange(of: model.expanded) { _, expanded in
            if !expanded {
                editingDuration = false
                if editingTask { commitTask() }
                focusedControl = nil
            }
        }
        .onChange(of: model.session.kind) { _, _ in editingTask = false }
        .onChange(of: model.session.phase) { _, phase in
            if phase != .idle { editingDuration = false }
        }
        .onExitCommand {
            if editingDuration { editingDuration = false }
            else if editingTask { cancelTask() } else { model.hide() }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Text(model.clock)
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(1 - presentation.expansion).accessibilityHidden(model.expanded)
                    .accessibilityLabel("\(phaseName) timer").accessibilityValue(remainingDescription)
                Text(phaseName).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7)).opacity(presentation.expansion)
                    .padding(.leading, 20)
                    .accessibilityHidden(!model.expanded)
            }
            .frame(width: (layout.width - layout.notchWidth) / 2)
            Color.clear.frame(width: layout.notchWidth).accessibilityHidden(true)
            ZStack(alignment: .trailing) {
                transportButton(diameter: 28, compact: true)
                    .frame(width: 36, height: 34).opacity(1 - presentation.expansion)
                    .padding(.trailing, trailingInset + 36)
                    .allowsHitTesting(!model.expanded && presentation.expansion < 0.01)
                    .accessibilityHidden(model.expanded)
                Button(action: model.toggleExpanded) {
                    Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 36, height: 34, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable().focusEffectDisabled()
                .focused($focusedControl, equals: .collapse)
                .padding(.trailing, trailingInset)
                .help(model.expanded ? "Collapse timer" : "Expand timer")
                .accessibilityLabel(model.expanded ? "Collapse timer" : "Expand timer")
            }
            .frame(width: (layout.width - layout.notchWidth) / 2, alignment: .trailing)
        }
        .frame(height: layout.headerHeight)
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    clockControl
                    Text(model.session.phase == .paused ? "Paused" : model.session.phase == .completed ? "Complete" : "")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        .frame(height: 16)
                        .accessibilityHidden(model.session.phase != .paused && model.session.phase != .completed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    transportButton(diameter: 52, compact: false)
                    Text(model.session.phase == .completed ? (model.isBreak ? "Focus again" : "5-min break") : "")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(height: 16)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityHidden(model.session.phase != .completed)
                }
                .frame(width: controlColumnWidth, alignment: .trailing)
            }
            .frame(height: 72)
            HStack(spacing: 8) {
                taskRow.frame(maxWidth: .infinity, alignment: .leading)
                if model.storageWarning != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        .help("Session recovery unavailable").accessibilityLabel("Session recovery unavailable")
                }
                Button {
                    if editingTask { commitTask() }
                    if model.isActive { model.stop() }
                    else if model.session.phase == .completed { model.finish() }
                    else { model.hide() }
                } label: {
                    Text(model.isActive ? "End" : model.session.phase == .completed ? "Close" : "Hide")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        .frame(width: controlColumnWidth, height: 28, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusEffectDisabled()
                .accessibilityLabel(model.isActive ? "End session" : model.session.phase == .completed ? "Close completed session" : "Hide timer")
            }
            .frame(height: 28)
        }
        .padding(.leading, 20).padding(.trailing, trailingInset).padding(.top, 12).padding(.bottom, 16)
        .frame(height: 140, alignment: .top)
        .background(Color(red: 0.12, green: 0.12, blue: 0.12))
    }

    private var clockText: some View {
        Text(model.clock).font(.system(size: 44, weight: .regular)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(height: 54)
            .accessibilityLabel("\(phaseName) timer").accessibilityValue(remainingDescription)
    }

    @ViewBuilder private var clockControl: some View {
        if model.session.phase == .idle {
            Button {
                durationInput = model.focusClock
                durationEditID = UUID()
                focusedControl = nil
                editingDuration = true
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    clockText
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle(restingOpacity: 1)).focusEffectDisabled()
            .padding(.leading, -8)
            .focused($focusedControl, equals: .duration)
            .help("Change focus duration")
            .accessibilityLabel("Change focus duration").accessibilityValue(model.focusClock)
            .popover(isPresented: $editingDuration, arrowEdge: .bottom) { durationPicker }
        } else { clockText }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus duration").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                InlineDurationEditor(initialSeconds: model.focusDurationSeconds,
                                     onTextChanged: { durationInput = $0 },
                                     onCommit: commitDuration, onCancel: { editingDuration = false })
                    .id(durationEditID).frame(width: 100, height: 32)
                Spacer()
                Button {
                    if let seconds = FocusDuration.parse(durationInput) { commitDuration(seconds) }
                } label: {
                    Text("Set").font(.system(size: 12, weight: .medium))
                        .frame(width: 44, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle()).focusEffectDisabled()
                .disabled(FocusDuration.parse(durationInput) == nil)
            }
            HStack(spacing: 6) {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button { commitDuration(minutes * 60) } label: {
                        Text("\(minutes)").font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(minutes * 60 == model.focusDurationSeconds ? 0.1 : 0)))
                    }
                    .buttonStyle(QuietButtonStyle()).focusEffectDisabled()
                    .accessibilityLabel("Set focus duration to \(minutes) minutes")
                }
            }
            Text(FocusDuration.parse(durationInput) == nil ? "Use minutes or mm:ss (e.g. 421:09)" : "Minutes : seconds")
                .font(.system(size: 11)).foregroundStyle(FocusDuration.parse(durationInput) == nil ? .orange : .white.opacity(0.65))
        }
        .padding(16).frame(width: 228)
        .background(Color(red: 0.16, green: 0.16, blue: 0.16))
        .preferredColorScheme(.dark).environment(\.colorScheme, .dark).focusEffectDisabled()
    }

    private func commitDuration(_ seconds: Int) {
        guard model.updateFocusDuration(seconds: seconds) else { return }
        editingDuration = false
        focusedControl = .primary
    }

    @ViewBuilder private var taskRow: some View {
        if model.isBreak {
            Text("Step away").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
        } else if editingTask {
            InlineTaskEditor(initialText: taskTitle, onTextChanged: { taskInput = $0 },
                             onCommit: { commitTask($0) }, onCancel: cancelTask)
                .id(taskEditID)
                .frame(maxWidth: 260, minHeight: 28)
        } else {
            Button(action: beginTaskEditing) {
                HStack(spacing: 5) {
                    Image(systemName: taskTitle.isEmpty ? "plus" : "pencil").font(.system(size: 11))
                    Text(taskTitle.isEmpty ? "Add task" : taskTitle).lineLimit(1)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8).frame(minHeight: 28).contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle()).focusEffectDisabled()
            .padding(.leading, -8)
            .help(taskTitle.isEmpty ? "Add a focus task" : "Edit focus task")
            .accessibilityLabel(taskTitle.isEmpty ? "Add focus task, optional" : "Edit focus task: \(taskTitle)")
        }
    }

    @ViewBuilder private func transportButton(diameter: CGFloat, compact: Bool) -> some View {
        let running = model.session.phase == .running
        let button = Button {
            if editingTask { commitTask() }
            if model.isActive { model.pauseOrResume() }
            else if model.session.phase == .completed && !model.isBreak { model.start(seconds: 300, kind: .rest) }
            else { model.start() }
        } label: {
            Image(systemName: running ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 11 : 20, weight: .semibold))
                .foregroundStyle(running ? orange : green)
                .offset(x: running ? 0 : diameter * 0.025)
                .frame(width: compact ? 36 : diameter, height: compact ? 34 : diameter).contentShape(Rectangle())
        }
        .buttonStyle(TransportButtonStyle(running: running, diameter: diameter))
        .focusable()
        .focusEffectDisabled()
        .focused($focusedControl, equals: compact ? .compactTransport : model.isActive ? .transport : .primary)
        .help(transportLabel).accessibilityLabel(transportLabel)
        if compact || editingTask || editingDuration { button } else { button.keyboardShortcut(.defaultAction) }
    }

    private func beginTaskEditing() {
        taskInput = taskTitle
        taskEditID = UUID()
        focusedControl = nil
        editingTask = true
    }

    private func commitTask(_ text: String? = nil) {
        guard editingTask else { return }
        editingTask = false
        model.updateTask(text ?? taskInput)
        focusedControl = model.isActive ? .transport : .primary
    }

    private func cancelTask() {
        editingTask = false
        focusedControl = model.isActive ? .transport : .primary
    }
}
