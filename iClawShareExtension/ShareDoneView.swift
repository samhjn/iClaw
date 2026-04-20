import SwiftUI

/// Success screen shown after a share was staged but the system wouldn't let
/// the extension foreground iClaw (Apple blocks share extensions from
/// calling `UIApplication.open` / `openURL:` on recent iOS). Tells the user
/// what to do next.
struct ShareDoneView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Saved to iClaw")
                    .font(.title3.weight(.semibold))
                Text("Open iClaw to continue the conversation — your files are already attached.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("iClaw")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
