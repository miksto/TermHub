import SwiftUI

/// A Label whose icon swaps to "shippingbox" when `showSandboxIcon` is true,
/// while maintaining stable width by always measuring both icons.
struct SandboxSwappableLabel: View {
    let title: String
    let systemImage: String
    let showSandboxIcon: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            ZStack {
                Image(systemName: systemImage)
                    .opacity(showSandboxIcon ? 0 : 1)
                Image(systemName: "shippingbox")
                    .opacity(showSandboxIcon ? 1 : 0)
            }
        }
        .font(.caption)
    }
}
