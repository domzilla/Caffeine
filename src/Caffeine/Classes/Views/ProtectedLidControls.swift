import SwiftUI

struct ProtectedLidControls: View {
    @ObservedObject var manager: ProtectedLidManager
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protected lid mode").font(.headline)
            Text(
                "Locks your Mac now, then keeps tasks running with the lid closed and displays off. Unlock with your Mac password or Touch ID when you return. Unlocking ends this mode."
            )
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            Text(
                "Requires administrator approval once to install a small helper. Later sessions need no administrator prompt. Normal sleep returns when Caffeine stops, the timer expires, or the app exits. Keep the Mac ventilated; this uses more battery than sleep."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if self.manager.isPreparing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing protected lid mode…")
                }
            } else if self.manager.isRunning {
                Text("Protected lid mode is active.").foregroundStyle(.secondary)
            }
            if let error = self.manager.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if self.manager.isEngaged {
                Button("Stop protected lid mode") { self.manager.stop() }
            } else {
                Button("Lock & keep awake with lid closed…", action: self.start)
            }
        }
    }
}
