import SwiftUI

/// Paleta kolorów, którymi użytkownik odróżnia systemy na liście.
///
/// Zapisywana jest **nazwa**, nie składowe koloru: dzięki temu konfiguracja pozostaje
/// czytelna, a kolory same dostrajają się do trybu jasnego i ciemnego.
enum SystemColor: String, CaseIterable, Identifiable {
    case blue, green, orange, purple, red, teal, pink, yellow, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red:    return .red
        case .teal:   return .teal
        case .pink:   return .pink
        case .yellow: return .yellow
        case .gray:   return .gray
        }
    }

    /// Nazwa do odczytania przez VoiceOver — sam kolor nie niesie informacji dla
    /// osoby, która go nie widzi.
    var label: LocalizedStringKey {
        switch self {
        case .blue:   return "Blue"
        case .green:  return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .red:    return "Red"
        case .teal:   return "Teal"
        case .pink:   return "Pink"
        case .yellow: return "Yellow"
        case .gray:   return "Gray"
        }
    }
}

/// Kółko z kolorem — wspólne dla listy i dla wyboru koloru.
struct ColorDot: View {
    let color: SystemColor
    var selected: Bool = false

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: 14, height: 14)
            .overlay(
                Circle().strokeBorder(.primary, lineWidth: selected ? 2 : 0)
            )
    }
}

/// Wybór koloru dla jednego systemu.
struct ColorPickerPopover: View {
    let current: SystemColor
    let onPick: (SystemColor) -> Void

    private let columns = [GridItem(.adaptive(minimum: 28))]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SystemColor.allCases) { option in
                    Button {
                        onPick(option)
                    } label: {
                        ColorDot(color: option, selected: option == current)
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                    .accessibilityLabel(option.label)
                }
            }
        }
        .padding(12)
        .frame(width: 180)
    }
}
