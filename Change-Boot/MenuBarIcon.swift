import SwiftUI

/// Ikona w pasku menu: dwa dyski jeden na drugim, z przesunięciem.
///
/// Kolory pochodzą z ikony programu — zmierzone z `finalico.png` w polu pod każdym
/// z dwóch dysków, nie dobrane na oko:
/// zieleń `#7CDAB2` pod dyskiem wypełnionym, fiolet `#8980DC` pod konturowym.
/// Dzięki temu pasek i ikona w Docku mówią tym samym językiem.
struct MenuBarIcon: View {

    static let zielen = Color(red: 0x7C/255, green: 0xDA/255, blue: 0xB2/255)
    static let fiolet = Color(red: 0x89/255, green: 0x80/255, blue: 0xDC/255)

    var body: some View {
        ZStack {
            // Dysk wewnętrzny idzie do tyłu i w górę, zewnętrzny na wierzch i w dół —
            // ten sam układ co na ikonie programu.
            Image(systemName: "internaldrive.fill")
                .foregroundStyle(Self.zielen)
                .offset(x: 2.5, y: -2.5)
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(Self.fiolet)
                .offset(x: -2.5, y: 2.5)
        }
        .imageScale(.medium)
        .accessibilityLabel(Text("Change-Boot"))
    }
}

#Preview {
    MenuBarIcon().padding()
}
