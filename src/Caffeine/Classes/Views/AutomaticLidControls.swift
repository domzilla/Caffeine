import SwiftUI

struct AutomaticLidControls: View {
    @ObservedObject var manager: AutomaticLidManager
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Automatic lid control", isOn: self.$isEnabled)
                .font(.system(size: 13))
            Text("Turns off screen and keyboard lighting when closed, and locks your Mac when opened.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 20)
                .fixedSize(horizontal: false, vertical: true)
            if self.isEnabled, self.manager.isPreparing {
                Text("Preparing…")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            if self.isEnabled, let error = self.manager.errorMessage {
                Text(error).font(.system(size: 11)).foregroundColor(.red)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
