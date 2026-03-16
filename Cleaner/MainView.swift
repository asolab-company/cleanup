import Photos
import SwiftUI
import UIKit

struct MainView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    let onGoPremium: () -> Void

    @State private var usedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 1
    @State private var usedStorageGB: Int = 0
    @State private var totalStorageGB: Int = 64
    @State private var photoCount: Int = 0
    @State private var videoCount: Int = 0
    @State private var showSettings = false
    @State private var showPhotoAccessDenied = false
    @State private var openedGalleryRoute: GalleryRoute?
    @State private var showSmartCheckLoading = false
    @State private var smartCheckReport: SmartCheckReport?

    var body: some View {
        ZStack {

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image("app_btn_settings")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(usedGigabytes()) GB")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(colorFromHex("101015"))

                        Spacer()

                        Text("of \(totalGigabytes()) GB")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(colorFromHex("66666D"))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(colorFromHex("B7C5F4"))
                                .frame(height: 24)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: progressGradientColors(),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: max(
                                        (proxy.size.width - 16)
                                            * progressValue(),
                                        0
                                    ),
                                    height: 16
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                    }
                    .frame(height: 40)
                }

                PrimaryActionButton(
                    title: "Smart Check",
                    isDisabled: false,
                    action: {
                        Task { await openSmartCheck() }
                    }
                )

                Spacer()

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ],
                    spacing: 16
                ) {
                    Button(action: {
                        Task { await openGallery(.photos) }
                    }) {
                        MainTileView(
                            imageName: "app_ic_photo",
                            title: "Photo",
                            subtitle: "\(photoCount) Items"
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        Task { await openGallery(.videos) }
                    }) {
                        MainTileView(
                            imageName: "app_ic_video",
                            title: "Video",
                            subtitle: "\(videoCount) Items"
                        )
                    }
                    .buttonStyle(.plain)

                    MainTileView(
                        imageName: "app_ic_lock",
                        title: "Calendar",
                        subtitle: "Soon"
                    )
                    MainTileView(
                        imageName: "app_ic_lock",
                        title: "Contacts",
                        subtitle: "Soon"
                    )
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }.background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .task {
            loadStorageInfo()
            await subscriptionManager.refreshSubscriptionStatus()
            await requestPhotoPermissionOnLaunch()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(
                subscriptionManager: subscriptionManager,
                onBack: { showSettings = false },
                onGoPremium: {
                    showSettings = false
                    onGoPremium()
                }
            )
        }
        .fullScreenCover(isPresented: $showPhotoAccessDenied) {
            PhotoAccessDeniedView(
                onClose: { showPhotoAccessDenied = false },
                onOpenSettings: {
                    Task { await providePhotoAccessFromDeniedScreen() }
                }
            )
        }
        .fullScreenCover(item: $openedGalleryRoute) { route in
            GallerySwipeView(
                kind: route.kind,
                onBack: { openedGalleryRoute = nil },
                titleOverride: route.title,
                assetIDs: route.assetIDs
            )
        }
        .fullScreenCover(isPresented: $showSmartCheckLoading) {
            SmartCheckLoadingView(
                onBack: { showSmartCheckLoading = false },
                onCompleted: { report in
                    showSmartCheckLoading = false
                    smartCheckReport = report
                }
            )
        }
        .fullScreenCover(item: $smartCheckReport) { report in
            SmartCheckResultView(
                report: report,
                onBack: { smartCheckReport = nil }
            )
        }
    }

    private func loadStorageInfo() {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )
            let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 1
            let free =
                (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let used = max(total - free, 0)

            usedBytes = used
            totalBytes = max(total, 1)

            let rawTotalGB = Double(totalBytes) / 1_000_000_000.0
            let rawUsedGB = Double(usedBytes) / 1_000_000_000.0
            let normalizedTotalGB = normalizedStorageTier(for: rawTotalGB)
            let normalizedUsedGB = min(
                max(Int(rawUsedGB.rounded()), 0),
                normalizedTotalGB
            )

            totalStorageGB = normalizedTotalGB
            usedStorageGB = normalizedUsedGB
        } catch {
            usedBytes = 0
            totalBytes = 1
            usedStorageGB = 0
            totalStorageGB = 64
        }
    }

    private func requestPhotoPermissionOnLaunch() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            fetchMediaCounts()
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(
                for: .readWrite
            )
            if newStatus == .authorized || newStatus == .limited {
                fetchMediaCounts()
            } else {
                photoCount = 0
                videoCount = 0
            }
        case .denied, .restricted:
            photoCount = 0
            videoCount = 0
        @unknown default:
            photoCount = 0
            videoCount = 0
        }
    }

    private func openSmartCheck() async {
        guard subscriptionManager.hasActiveSubscription else {
            onGoPremium()
            return
        }
        if await ensurePhotoPermission() {
            showSmartCheckLoading = true
        } else {
            showPhotoAccessDenied = true
        }
    }

    private func openGallery(_ kind: GallerySwipeView.MediaKind) async {
        guard subscriptionManager.hasActiveSubscription else {
            onGoPremium()
            return
        }
        if await ensurePhotoPermission() {
            openedGalleryRoute = GalleryRoute(
                kind: kind,
                title: nil,
                assetIDs: nil
            )
        } else {
            showPhotoAccessDenied = true
        }
    }

    private func ensurePhotoPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(
                for: .readWrite
            )
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func providePhotoAccessFromDeniedScreen() async {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            await MainActor.run {
                UIApplication.shared.open(settingsURL)
            }
        }
    }

    private func fetchMediaCounts() {
        photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
        videoCount = PHAsset.fetchAssets(with: .video, options: nil).count
    }

    private func usedGigabytes() -> Int {
        usedStorageGB
    }

    private func totalGigabytes() -> Int {
        totalStorageGB
    }

    private func progressValue() -> Double {
        guard totalStorageGB > 0 else { return 0 }
        return min(max(Double(usedStorageGB) / Double(totalStorageGB), 0), 1)
    }

    private func progressGradientColors() -> [Color] {
        let percent = Int((progressValue() * 100).rounded(.down))

        switch percent {
        case 90...100:
            return [colorFromHex("FF3B30"), colorFromHex("D70015")]
        case 80..<90:
            return [colorFromHex("FF5A4F"), colorFromHex("F0323A")]
        case 70..<80:
            return [colorFromHex("FF7B5C"), colorFromHex("FF4F42")]
        case 60..<70:
            return [colorFromHex("FFA24D"), colorFromHex("FF7A2D")]
        case 50..<60:
            return [colorFromHex("FFC857"), colorFromHex("FFA726")]
        case 40..<50:
            return [colorFromHex("E7D95A"), colorFromHex("D4BE36")]
        case 30..<40:
            return [colorFromHex("B4D863"), colorFromHex("8BC34A")]
        case 20..<30:
            return [colorFromHex("7ECF7A"), colorFromHex("4CAF50")]
        case 10..<20:
            return [colorFromHex("4CB8D8"), colorFromHex("2D9CDB")]
        default:
            return [colorFromHex("3873E9"), colorFromHex("6A3FFF")]
        }
    }

    private func normalizedStorageTier(for rawTotalGB: Double) -> Int {
        let tiers = [16, 32, 64, 128, 256, 512, 1024, 2048]
        for tier in tiers {
            if rawTotalGB <= Double(tier) * 1.08 {
                return tier
            }
        }
        return max(Int((rawTotalGB / 256.0).rounded(.up)) * 256, 2048)
    }
}

private struct GalleryRoute: Identifiable {
    let id = UUID()
    let kind: GallerySwipeView.MediaKind
    let title: String?
    let assetIDs: [String]?
}

private struct MainTileView: View {
    let imageName: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)

                Spacer()
            }

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colorFromHex("101015"))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .padding(.leading, 5)

            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(colorFromHex("66666D"))
                .padding(.leading, 5)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(height: 154)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorFromHex("FFFFFF", alpha: 0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            colorFromHex("FFFFFF", alpha: 0.65),
                            lineWidth: 2
                        )
                )
        )
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(
            subscriptionManager: SubscriptionManager(),
            onGoPremium: {}
        )
    }
}

private struct PhotoAccessDeniedView: View {
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    @State private var showSettingsAlert = false

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            Image("app_ic_phot")
                .resizable()
                .scaledToFit()
                .frame(height: DeviceTraits.isSmallDevice ? 250 : 316)

            Spacer()

            Text("You did not provide\naccess to your gallery.")
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 26 : 32,
                        weight: .bold
                    )
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(colorFromHex("101015"))
                .lineSpacing(2)
                .padding(.horizontal, 24)

            Text("Without it, we cannot clean your gallery.")
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 14 : 16,
                        weight: .regular
                    )
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(colorFromHex("66666D"))
                .padding(.top, 14)
                .padding(.bottom, 30)

            PrimaryActionButton(
                title: "Provide access",
                isDisabled: false,
                action: { showSettingsAlert = true }
            )
            .padding(.horizontal, 22)

        }
        .padding(.bottom)
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .alert("Gallery Access Required", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                onOpenSettings()
            }
            Button("Close", role: .cancel) {
                onClose()
            }
        } message: {
            Text("Please allow photo access in Settings to continue.")
        }
    }
}

struct PhotoAccessDeniedView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoAccessDeniedView(
            onClose: {},
            onOpenSettings: {}
        )
    }
}
