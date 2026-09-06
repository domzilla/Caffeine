import SwiftUI

struct AutomaticLidControls: View {
    @ObservedObject var manager: AutomaticLidManager
    let isActive: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automatic lid control").font(.headline)
            Text(
                "While Caffeine is active, closing the lid sets the display and keyboard brightness to zero and keeps the Mac awake without locking. Opening the lid locks your Mac, then restores the previous brightness. Caffeine stays active for the next lid cycle."
            )
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text(
                "The helper needs administrator approval only for its first installation. Activation does not lock your Mac. Keep the laptop ventilated while it works with the lid closed."
            )
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if self.manager.isPreparing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing automatic lid control…")
                }
            } else if self.manager.isRunning {
                Text("Ready: lights off on close, lock on open.").foregroundStyle(.secondary)
            }
            if let error = self.manager.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(
                self.isActive ? String(localized: "Deactivate Caffeine") : String(localized: "Activate Caffeine"),
                action: self.toggle
            )
        }
    }
}
