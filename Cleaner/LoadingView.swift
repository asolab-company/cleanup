import SwiftUI

struct LoadingView: View {
    let onCompleted: () -> Void

    @State private var progress: Double = 0
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        Image("app_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 170, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            .shadow(
                color: colorFromHex("000000", alpha: 0.20),
                radius: 10,
                y: 5
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(colorFromHex("3873E9"))
                        .frame(maxWidth: 250)
                        .scaleEffect(x: 1, y: 1.6, anchor: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(colorFromHex("ABB7EF"))
                                .frame(height: 8)
                        )

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(colorFromHex("8585AD"))
                }
                .padding(.horizontal, 24)
                .padding(.bottom)
            }
            .onAppear(perform: startLoading)
            .onDisappear {
                loadingTask?.cancel()
                loadingTask = nil
            }
            .background(
                Image("app_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
    }

    private func startLoading() {
        loadingTask?.cancel()
        progress = 0

        loadingTask = Task {
            let startedAt = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let nextProgress = min(elapsed / 1.5, 1.0)

                await MainActor.run {
                    progress = nextProgress
                }

                if nextProgress >= 1.0 {
                    break
                }

                try? await Task.sleep(
                    nanoseconds: UInt64((1.0 / 60.0) * 1_000_000_000)
                )
            }

            guard !Task.isCancelled else { return }
            onCompleted()
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView(onCompleted: {})
    }
}
