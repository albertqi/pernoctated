import SwiftUI

enum AppStyle {
    static let accent = Color("AccentColor")
    static let buttonFill = Color(red: 0.122, green: 0.365, blue: 0.365)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 19)
            .foregroundStyle(.white)
            .background(AppStyle.buttonFill.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 18))
    }
}
