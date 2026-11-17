import SwiftUI

struct ShelfLEDTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let blue = Color(red: 0.48, green: 0.82, blue: 1)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.07)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6.8)
            let flickering = (4.72...4.86).contains(cycle) || (5.02...5.09).contains(cycle)
                || (5.23...5.37).contains(cycle)
            let power = reduceMotion ? 1.0 : flickering ? 0.18 : 1.0
            HStack(alignment: .center, spacing: 7) {
                neonWord("JIMBO'S", power: 1)
                neonWord("SHELF", power: power)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.40), in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(blue.opacity(0.25), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Jimbo's Shelf")
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func neonWord(_ word: String, power: Double) -> some View {
        Text(word)
            .font(.custom("AvenirNextCondensed-Heavy", size: 24))
            .tracking(1.1)
            .foregroundStyle(Color(red: 0.70, green: 0.94, blue: 1))
            .shadow(color: blue.opacity(power), radius: 1)
            .shadow(color: blue.opacity(0.9 * power), radius: 4)
            .shadow(color: blue.opacity(0.6 * power), radius: 10)
            .opacity(power)
            .fixedSize()
    }

}

struct ShelfLEDButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    private let blue = Color(red: 0.48, green: 0.82, blue: 1)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(blue.opacity(configuration.isPressed ? 0.22 : 0.07), in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(blue.opacity(configuration.isPressed ? 0.8 : 0.25), lineWidth: 1)
            }
            .shadow(color: blue.opacity(configuration.isPressed ? 0.32 : 0), radius: 5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
