import SwiftUI

enum ShioButtonStyle {
    case primary
    case secondary
    case text
    case destructive
}

struct ShioButton: View {
    let title: String
    let style: ShioButtonStyle
    let action: () -> Void

    @State private var isPressed = false

    init(_ title: String, style: ShioButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: {
            ShioHaptic.light()
            action()
        }) {
            Text(title)
                .font(ShioFont.bodyEmphasis)
                .foregroundStyle(foreground)
                .padding(.vertical, ShioPadding.buttonVertical)
                .padding(.horizontal, ShioPadding.buttonHorizontal)
                .frame(minHeight: ShioPadding.tapTargetMin)
                .frame(maxWidth: style == .text ? nil : .infinity)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: style == .secondary ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary:     return ShioColor.Chrome.background
        case .secondary:   return ShioColor.Text.primary
        case .text:        return ShioColor.Text.primary
        case .destructive: return .white
        }
    }

    private var background: Color {
        switch style {
        case .primary:     return ShioColor.Text.primary
        case .secondary:   return ShioColor.Chrome.fill
        case .text:        return .clear
        case .destructive: return ShioColor.State.danger
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: return ShioColor.Chrome.border
        default:         return .clear
        }
    }
}
