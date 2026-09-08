import SwiftUI
import SwiftData

/// The Mac's first run.
///
/// The Mac never had one: it dropped you on an empty dashboard and left you to
/// infer what a project was for. Four screens, one idea each, then the app.
///
/// Deliberately short, because on a Mac almost nothing is actually required.
/// There is no key to install, no machine to add, and "This Mac" already exists
/// as a synced host. The only step that matters is choosing a folder, so three
/// screens explain the idea and the fourth is the single action.
///
/// Vocabulary is folder, project, machine, terminal. Never repo, SSH, tmux or
/// host: those are words the app can teach later, once something is running.
/// Skip is present on every screen and never buried.
struct MacOnboarding: View {

    /// Set once the pass is finished or skipped, so it never runs twice.
    static let completedKey = "shio.mac.onboarded"

    let onOpenFolder: () -> Void
    let onCloneFromLink: () -> Void
    let onConnectMachine: () -> Void
    let onFinish: () -> Void

    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        ZStack {
            ShioTheme.background.ignoresSafeArea()

            Group {
                switch step {
                case 0:  whatItIs
                case 1:  howWorkIsOrganised
                case 2:  itKeepsRunning
                default: startWithAFolder
                }
            }
            .frame(maxWidth: 460)
            .transition(.opacity)

            VStack {
                Spacer()
                HStack {
                    // Back sits opposite Skip so the two never move; the pips
                    // between them are the third way to navigate.
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                    Spacer()
                    pips
                    Spacer()
                    if step < lastStep {
                        Button("Skip", action: finish)
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: step)
        // Arrow keys move too, so the pass is navigable without aiming at
        // anything. The last screen's choices are actions, not a next step, so
        // right does nothing there rather than skipping past them.
        .focusable()
        .onKeyPress(.leftArrow)  { if step > 0 { step -= 1 }; return .handled }
        .onKeyPress(.rightArrow) { if step < lastStep { step += 1 }; return .handled }
    }

    // MARK: screens

    private var whatItIs: some View {
        screen {
            Text("塩")
                .font(.system(size: 40))
                .foregroundStyle(ShioTheme.textPrimary)
            Text("shio")
                .font(.system(size: 14, design: .monospaced))
                .tracking(3)
                .foregroundStyle(ShioTheme.textSecondary)
                .padding(.bottom, 10)
            title("Your machines, in your pocket.")
            body("Shio is a terminal that works the same on your Mac, your iPhone, and your iPad. "
                 + "Start something on one and pick it up on another.")
            continueButton
        }
    }

    private var howWorkIsOrganised: some View {
        screen {
            title("Work lives in projects")
            body("A project is a folder you work in. Shio keeps a terminal waiting in each one, "
                 + "so you are never hunting for the right window.")
            // Shown rather than described: two rows in the shape the app uses,
            // each carrying its own identity tint like the real thing.
            VStack(spacing: 6) {
                exampleRow(name: "shio", detail: "main · 2 uncommitted")
                exampleRow(name: "landing", detail: "main · clean")
            }
            .frame(width: 250)
            .padding(.vertical, 4)
            continueButton
        }
    }

    private var itKeepsRunning: some View {
        screen {
            title("It keeps running without you")
            body("Step away from your desk and the work carries on. Pick up your phone and you are "
                 + "in the same session, exactly where you left it.")
            OneSessionThreeDevices()
                .padding(.top, 6)
                .padding(.bottom, 2)
            // The condition belongs here, small, as an upgrade rather than a
            // hedge in the promise. A closed laptop really is unreachable, and
            // a machine that never sleeps is what makes the promise unqualified.
            Text("Best with a machine that stays awake. A spare Mac, a server, or a small Pi.")
                .font(.system(size: 11.5))
                .foregroundStyle(ShioTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            continueButton
        }
    }

    private var startWithAFolder: some View {
        screen {
            title("Start with a folder")
            body("Open one and Shio keeps a terminal there, ready on this Mac and on your phone.")
            VStack(spacing: 7) {
                choice("Open a folder on this Mac", "The usual way to start",
                       glyph: "folder", lead: true) { finish(); onOpenFolder() }
                choice("Clone from a GitHub link", "Or GitLab, Bitbucket, or your own server",
                       glyph: "arrow.down.circle") { finish(); onCloneFromLink() }
                choice("Connect another machine", "A server, a Pi, or another Mac that stays awake",
                       glyph: "desktopcomputer") { finish(); onConnectMachine() }
            }
            .frame(maxWidth: 340)
            .padding(.top, 2)
        }
    }

    // MARK: pieces

    private func screen<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 9) { content() }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 34)
    }

    private func title(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(ShioTheme.textPrimary)
    }

    private func body(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13))
            .foregroundStyle(ShioTheme.textSecondary)
            .lineSpacing(2)
            .frame(maxWidth: 340)
    }

    private var continueButton: some View {
        ShioButton(step == lastStep ? "Get started" : "Continue", .primary) {
            if step < lastStep { step += 1 } else { finish() }
        }
        .padding(.top, 8)
    }

    private func exampleRow(name: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Text("⎇")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ProjectIdentity.color(for: name))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ShioTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ShioTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(ShioTheme.line))
    }

    private func choice(_ head: String, _ sub: String, glyph: String,
                        lead: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: glyph)
                    .font(.system(size: 13))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(head)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ShioTheme.textPrimary)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(lead ? ShioTheme.hover : ShioTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ShioTheme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tappable, so any screen is reachable from any other. A first run you can
    /// only move forward through is one you cannot re-read.
    private var pips: some View {
        HStack(spacing: 7) {
            ForEach(0...lastStep, id: \.self) { i in
                Button { step = i } label: {
                    Circle()
                        .fill(i == step ? ShioTheme.accent : ShioTheme.line)
                        .frame(width: 5, height: 5)
                        // A 5pt dot is not a click target; pad it to something
                        // a pointer can actually hit.
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(i + 1)")
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinish()
    }
}

/// The offer to put this on your phone, shown once the first project exists.
///
/// Deliberately not part of the guided pass. Pairing needs the iPhone app
/// already installed, so asking during first run means "stop, find your phone,
/// install something, come back" before Shio has done anything at all. After a
/// terminal is open the offer means something, and it can be ignored forever.
struct MacPhoneOffer: View {
    static let dismissedKey = "shio.mac.phoneOfferDismissed"

    let onPair: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "iphone")
                .font(.system(size: 15))
                .foregroundStyle(ShioTheme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Use this on your phone")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ShioTheme.textPrimary)
                Text("Scan a code and the same terminal is in your pocket.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            Spacer(minLength: 8)
            Button("Show code", action: onPair)
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textPrimary)
            Button("Not now") {
                UserDefaults.standard.set(true, forKey: Self.dismissedKey)
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ShioTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ShioTheme.line))
    }
}

/// Three devices showing ONE session.
///
/// The point of the picture is sameness, so all three screens draw the identical
/// content and share a single blinking cursor driven off one clock. Different
/// content in each would read as three separate terminals, which is the opposite
/// of the claim. Hairline frames and the project tint keep it in the same
/// language as the rail, not an illustration bolted on.
private struct OneSessionThreeDevices: View {
    var body: some View {
        // One TimelineView for all three, so the cursors blink in lockstep.
        TimelineView(.periodic(from: .now, by: 0.55)) { ctx in
            let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            HStack(alignment: .bottom, spacing: 16) {
                mac(cursorOn: on)
                pad(cursorOn: on)
                phone(cursorOn: on)
            }
        }
        .frame(height: 74)
    }

    // MARK: devices

    private func mac(cursorOn: Bool) -> some View {
        VStack(spacing: 0) {
            screen(width: 104, height: 64, cursorOn: cursorOn, scale: 1)
            // The lid hinge, so the shape reads as a laptop rather than a slab.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(ShioTheme.line)
                .frame(width: 122, height: 3)
        }
    }

    private func pad(cursorOn: Bool) -> some View {
        screen(width: 58, height: 46, cursorOn: cursorOn, scale: 0.82)
    }

    private func phone(cursorOn: Bool) -> some View {
        screen(width: 32, height: 56, cursorOn: cursorOn, scale: 0.72)
    }

    // MARK: one screen

    private func screen(width: CGFloat, height: CGFloat, cursorOn: Bool, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            // The same project mark the rail and terminal header use.
            HStack(spacing: 3 * scale) {
                Text("⎇")
                    .font(.system(size: 7 * scale, design: .monospaced))
                    .foregroundStyle(ProjectIdentity.color(for: "shio"))
                bar(width: 15 * scale, opacity: 0.5)
            }
            bar(width: 26 * scale, opacity: 0.28)
            bar(width: 19 * scale, opacity: 0.28)
            HStack(spacing: 2 * scale) {
                bar(width: 9 * scale, opacity: 0.28)
                Rectangle()
                    .fill(ShioTheme.textSecondary)
                    .frame(width: 3 * scale, height: 5 * scale)
                    .opacity(cursorOn ? 0.9 : 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 6 * scale)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ShioTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(ShioTheme.line))
    }

    private func bar(width: CGFloat, opacity: Double) -> some View {
        Capsule().fill(ShioTheme.textTertiary.opacity(opacity))
            .frame(width: width, height: 2.5)
    }
}
