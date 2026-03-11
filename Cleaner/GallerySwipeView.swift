import AVFoundation
import AVKit
import ImageIO
import Photos
import SwiftUI
import UIKit

struct GallerySwipeView: View {
    enum MediaKind: String, Identifiable {
        case photos
        case videos

        var id: String { rawValue }

        var title: String {
            switch self {
            case .photos: return "Photos"
            case .videos: return "Videos"
            }
        }

        var mediaType: PHAssetMediaType {
            switch self {
            case .photos: return .image
            case .videos: return .video
            }
        }
    }

    let kind: MediaKind
    let onBack: () -> Void
    let titleOverride: String?
    let assetIDs: [String]?

    init(
        kind: MediaKind,
        onBack: @escaping () -> Void,
        titleOverride: String? = nil,
        assetIDs: [String]? = nil
    ) {
        self.kind = kind
        self.onBack = onBack
        self.titleOverride = titleOverride
        self.assetIDs = assetIDs
    }

    @State private var assets: [PHAsset] = []
    @State private var currentIndex = 0
    @State private var currentImage: UIImage?
    @State private var nextImage: UIImage?
    @State private var dragOffset: CGSize = .zero
    @State private var savedCount = 0
    @State private var deletedCount = 0
    @State private var markedForDeletionIDs: Set<String> = []
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var sharePayload: SharePayload?
    @State private var noteByAssetID: [String: String] = [:]
    @State private var showNoteSheet = false
    @State private var noteDraft = ""
    @State private var showInfoSheet = false
    @State private var infoDateText = ""
    @State private var infoFilenameText = ""
    @State private var infoDeviceText = ""
    @State private var infoLensText = ""
    @State private var infoDimensionsText = ""
    @State private var infoNoteText = ""
    @State private var showMarkedDeletionView = false
    @State private var showDeletionSuccessView = false
    @State private var videoPlaybackSession: VideoPlaybackSession?

    private let notesStorageKey = "gallery_note_by_asset_id"

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(50)

            GeometryReader { proxy in
                ZStack {
                    if hasCurrentAsset {
                        ZStack {
                            mediaCard(
                                image: nextImage,
                                width: proxy.size.width - 44,
                                height: proxy.size.height - 8
                            )
                            .scaleEffect(0.97)
                            .offset(y: 7)
                            .opacity(nextImage == nil ? 0 : 1)

                            mediaCard(
                                image: currentImage,
                                width: proxy.size.width - 44,
                                height: proxy.size.height - 8
                            )
                            .offset(x: dragOffset.width)
                            .rotationEffect(
                                .degrees(Double(dragOffset.width / 22))
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        if value.translation.width > 110 {
                                            swipeDecision(save: true)
                                        } else if value.translation.width < -110
                                        {
                                            swipeDecision(save: false)
                                        } else {
                                            withAnimation(
                                                .spring(
                                                    response: 0.25,
                                                    dampingFraction: 0.82
                                                )
                                            ) {
                                                dragOffset = .zero
                                            }
                                        }
                                    }
                            )
                        }
                        .overlay(alignment: .trailing) {
                            VStack(spacing: 18) {
                                sideIconButton(
                                    imageName: isCurrentAssetLiked
                                        ? "app_ic_swipe_5" : "app_ic_swipe_1",
                                    action: {
                                        Task {
                                            await toggleLikeForCurrentAsset()
                                        }
                                    }
                                )
                                sideIconButton(
                                    imageName: "app_ic_swipe_4",
                                    action: {
                                        Task { await shareCurrentAsset() }
                                    }
                                )
                                sideIconButton(
                                    imageName: "app_ic_swipe_3",
                                    action: {
                                        openNoteSheetForCurrentAsset()
                                    }
                                )
                                sideIconButton(
                                    imageName: "app_ic_swipe_2",
                                    action: {
                                        Task {
                                            await openInfoSheetForCurrentAsset()
                                        }
                                    }
                                )
                            }
                            .padding(.trailing, 14)
                        }
                        .overlay(alignment: .center) {
                            if isCurrentAssetVideo {
                                Button {
                                    Task { await playCurrentVideo() }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 68, height: 68)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        colorFromHex(
                                                            "FFFFFF",
                                                            alpha: 0.55
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                            .shadow(
                                                color: colorFromHex(
                                                    "101015",
                                                    alpha: 0.18
                                                ),
                                                radius: 8,
                                                y: 3
                                            )
                                        Image(systemName: "play.fill")
                                            .font(
                                                .system(
                                                    size: 28,
                                                    weight: .semibold
                                                )
                                            )
                                            .foregroundStyle(
                                                colorFromHex("FFFFFF")
                                            )
                                            .padding(.leading, 4)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(width: 68, height: 68)
                                .contentShape(Circle())
                                .zIndex(20)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text(
                                "No \(kind == .photos ? "photos" : "videos") found"
                            )
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(colorFromHex("101015"))
                            Text("0 deleted / 0 saved")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(colorFromHex("8585AD"))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .padding(.bottom, 8)

            bottomControls
        }
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .task {
            loadAssets()
            prepareInitialImages()
            loadSavedNotes()
        }
        .sheet(item: $sharePayload) { payload in
            ActivityViewController(activityItems: payload.items)
        }
        .fullScreenCover(isPresented: $showMarkedDeletionView) {
            MarkedForDeletionView(
                assets: markedAssets,
                onClose: { showMarkedDeletionView = false },
                onUnmark: { id in
                    markedForDeletionIDs.remove(id)
                },
                onDelete: {
                    Task { await deleteMarkedAssets() }
                }
            )
        }
        .fullScreenCover(isPresented: $showDeletionSuccessView) {
            DeletionSuccessView {
                showDeletionSuccessView = false
                onBack()
            }
        }
        .fullScreenCover(item: $videoPlaybackSession) { session in
            VideoPlayerView(
                player: session.player,
                onClose: {
                    session.player.pause()
                    videoPlaybackSession = nil
                }
            )
        }
        .overlay {
            if showNoteSheet {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showNoteSheet = false
                            }
                        }

                    noteSheet
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                }
                .animation(.easeInOut(duration: 0.2), value: showNoteSheet)
            } else if showInfoSheet {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showInfoSheet = false
                            }
                        }

                    infoSheet
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                }
                .animation(.easeInOut(duration: 0.2), value: showInfoSheet)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: {
                onBack()
            }) {
                Image("app_ic_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .zIndex(10)

            Spacer()

            VStack(spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(colorFromHex("101015"))
                Text("\(displayedIndex) / \(assets.count)")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(colorFromHex("66666D"))
            }

            Spacer()
            Button {
                showMarkedDeletionView = true
            } label: {
                Image("app_ic_trash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .frame(width: 56, height: 56)
                    .opacity(markedForDeletionIDs.isEmpty ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .zIndex(10)
            .disabled(markedForDeletionIDs.isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var headerTitle: String {
        titleOverride ?? kind.title
    }

    private var bottomControls: some View {
        VStack(spacing: 18) {
            HStack {
                Button(action: { buttonDecision(save: false) }) {
                    Image("app_btn_delete")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.plain)
                .disabled(!hasCurrentAsset)
                .opacity(hasCurrentAsset ? 1 : 0.5)

                Spacer()

                Button(action: { buttonDecision(save: true) }) {
                    Image("app_btn_keep")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.plain)
                .disabled(!hasCurrentAsset)
                .opacity(hasCurrentAsset ? 1 : 0.5)
            }
            .padding(.horizontal, 40)

            Text("\(deletedCount) deleted / \(savedCount) saved")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colorFromHex("8585AD"))
                .padding(.bottom, 10)
        }
        .padding(.top, 16)
    }

    private var hasCurrentAsset: Bool {
        currentIndex < assets.count
    }

    private var displayedIndex: Int {
        guard !assets.isEmpty, hasCurrentAsset else { return 0 }
        return currentIndex + 1
    }

    private var currentAssetID: String? {
        guard hasCurrentAsset else { return nil }
        return assets[currentIndex].localIdentifier
    }

    private var markedAssets: [PHAsset] {
        assets.filter { markedForDeletionIDs.contains($0.localIdentifier) }
    }

    private var hasSavedNoteForCurrentAsset: Bool {
        guard let id = currentAssetID else { return false }
        let value = noteByAssetID[id] ?? ""
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCurrentAssetLiked: Bool {
        guard hasCurrentAsset else { return false }
        let asset = assets[currentIndex]
        return favoriteOverrides[asset.localIdentifier] ?? asset.isFavorite
    }

    private var isCurrentAssetVideo: Bool {
        guard hasCurrentAsset else { return false }
        return assets[currentIndex].mediaType == .video
    }

    private func loadAssets() {
        var result: [PHAsset] = []
        if let assetIDs {
            let fetch = PHAsset.fetchAssets(
                withLocalIdentifiers: assetIDs,
                options: nil
            )
            fetch.enumerateObjects { asset, _, _ in
                result.append(asset)
            }
            let orderMap = Dictionary(
                uniqueKeysWithValues: assetIDs.enumerated().map { ($1, $0) }
            )
            result.sort { (left, right) in
                (orderMap[left.localIdentifier] ?? .max)
                    < (orderMap[right.localIdentifier] ?? .max)
            }
        } else {
            let options = PHFetchOptions()
            options.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
            let fetchResult = PHAsset.fetchAssets(
                with: kind.mediaType,
                options: options
            )
            fetchResult.enumerateObjects { asset, _, _ in
                result.append(asset)
            }
        }
        assets = result
        favoriteOverrides = Dictionary(
            uniqueKeysWithValues: result.map {
                ($0.localIdentifier, $0.isFavorite)
            }
        )
    }

    private func loadSavedNotes() {
        let saved =
            UserDefaults.standard.dictionary(forKey: notesStorageKey)
            as? [String: String]
        noteByAssetID = saved ?? [:]
    }

    private func saveNotes() {
        UserDefaults.standard.set(noteByAssetID, forKey: notesStorageKey)
    }

    private func mediaCard(image: UIImage?, width: CGFloat, height: CGFloat)
        -> some View
    {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay(ProgressView())
                    .frame(width: width, height: height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colorFromHex("FFFFFF", alpha: 0.55), lineWidth: 1)
        )
        .shadow(color: colorFromHex("101015", alpha: 0.08), radius: 6, y: 2)
    }

    private func prepareInitialImages() {
        guard hasCurrentAsset else {
            currentImage = nil
            nextImage = nil
            return
        }
        loadImage(for: currentIndex) { image in
            currentImage = image
        }
        preloadNextImage()
    }

    private func preloadNextImage() {
        let nextIndex = currentIndex + 1
        guard nextIndex < assets.count else {
            nextImage = nil
            return
        }
        loadImage(for: nextIndex) { image in
            nextImage = image
        }
    }

    private func loadImage(
        for index: Int,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard index >= 0, index < assets.count else {
            completion(nil)
            return
        }

        let asset = assets[index]
        let expectedID = asset.localIdentifier
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard index < assets.count,
                assets[index].localIdentifier == expectedID
            else {
                return
            }
            completion(image)
        }
    }

    private func buttonDecision(save: Bool) {
        guard hasCurrentAsset else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            dragOffset = CGSize(width: save ? 420 : -420, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            advance(save: save)
        }
    }

    private func swipeDecision(save: Bool) {
        guard hasCurrentAsset else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            dragOffset = CGSize(width: save ? 420 : -420, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            advance(save: save)
        }
    }

    private func advance(save: Bool) {
        let swipedAsset = hasCurrentAsset ? assets[currentIndex] : nil

        if save {
            savedCount += 1
            if let id = swipedAsset?.localIdentifier {
                markedForDeletionIDs.remove(id)
            }
        } else {
            deletedCount += 1
            if let id = swipedAsset?.localIdentifier {
                markedForDeletionIDs.insert(id)
            }
        }

        guard currentIndex < assets.count else { return }
        currentIndex += 1
        dragOffset = .zero

        if hasCurrentAsset {
            currentImage = nextImage
            preloadNextImage()
        } else {
            currentImage = nil
            nextImage = nil
        }
    }

    private func deleteMarkedAssets() async {
        let ids = markedForDeletionIDs
        guard !ids.isEmpty else { return }

        let assetsToDelete = assets.filter { ids.contains($0.localIdentifier) }
        guard !assetsToDelete.isEmpty else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }

            await MainActor.run {
                assets.removeAll { ids.contains($0.localIdentifier) }
                markedForDeletionIDs.removeAll()
                showMarkedDeletionView = false
                showDeletionSuccessView = true

                if currentIndex >= assets.count {
                    currentIndex = max(assets.count - 1, 0)
                }
                dragOffset = .zero
                prepareInitialImages()
            }
        } catch {
            return
        }
    }

    private func sideIconButton(imageName: String, action: (() -> Void)? = nil)
        -> some View
    {
        Button(action: {
            action?()
        }) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .zIndex(20)
    }

    private func toggleLikeForCurrentAsset() async {
        guard hasCurrentAsset else { return }
        let asset = assets[currentIndex]
        let id = asset.localIdentifier
        let nextValue = !(favoriteOverrides[id] ?? asset.isFavorite)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = nextValue
            }
            await MainActor.run {
                favoriteOverrides[id] = nextValue
            }
        } catch {
            return
        }
    }

    private func shareCurrentAsset() async {
        guard hasCurrentAsset else { return }
        let asset = assets[currentIndex]
        if let item = await loadShareItem(for: asset) {
            await MainActor.run {
                sharePayload = SharePayload(items: [item])
            }
        }
    }

    private func loadShareItem(for asset: PHAsset) async -> Any? {
        if asset.mediaType == .image {
            return await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                options.version = .current

                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, _ in
                    if let data, let image = UIImage(data: data) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        if asset.mediaType == .video {
            return await withCheckedContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat

                PHImageManager.default().requestAVAsset(
                    forVideo: asset,
                    options: options
                ) { avAsset, _, _ in
                    if let urlAsset = avAsset as? AVURLAsset {
                        continuation.resume(returning: urlAsset.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        return nil
    }

    private func playCurrentVideo() async {
        guard hasCurrentAsset else { return }
        let asset = assets[currentIndex]
        guard asset.mediaType == .video else { return }

        var playerItem = await loadVideoPlayerItemFallback(for: asset)
        if playerItem == nil {
            playerItem = await loadVideoPlayerItem(for: asset)
        }
        guard let playerItem else {
            return
        }

        _ = await waitUntilReadyToPlay(playerItem, timeoutSeconds: 2.5)

        await MainActor.run {
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
            videoPlaybackSession = VideoPlaybackSession(player: player)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                player.play()
            }
        }
    }

    private func waitUntilReadyToPlay(
        _ item: AVPlayerItem,
        timeoutSeconds: Double
    ) async -> Bool {
        if item.status == .readyToPlay { return true }
        if item.status == .failed { return false }

        let iterations = max(Int(timeoutSeconds / 0.1), 1)
        for _ in 0..<iterations {
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return item.status == .readyToPlay
    }

    private func loadVideoPlayerItem(for asset: PHAsset) async -> AVPlayerItem?
    {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestPlayerItem(
                forVideo: asset,
                options: options
            ) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func loadVideoPlayerItemFallback(for asset: PHAsset) async
        -> AVPlayerItem?
    {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                guard let avAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: AVPlayerItem(asset: avAsset))
            }
        }
    }

    private func openNoteSheetForCurrentAsset() {
        guard let id = currentAssetID else { return }
        noteDraft = noteByAssetID[id] ?? ""
        showNoteSheet = true
    }

    private func openInfoSheetForCurrentAsset() async {
        guard hasCurrentAsset else { return }
        let asset = assets[currentIndex]
        await prepareInfoSheetData(for: asset)
        showInfoSheet = true
    }

    private func prepareInfoSheetData(for asset: PHAsset) async {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEEE • MMM d, yyyy • h:mm a"

        let filename =
            PHAssetResource.assetResources(for: asset).first?.originalFilename
            ?? "Unknown"
        let baseDevice = asset.mediaType == .video ? "Video" : "Photo"
        let baseLens = asset.mediaType == .video ? "Video File" : "Image File"
        var cameraModel = baseDevice
        var lensModel = baseLens
        let pixelText = "\(asset.pixelWidth) × \(asset.pixelHeight)"
        var sizeText = "..."

        if asset.mediaType == .image {
            let details = await loadImageMetadataDetails(for: asset)
            cameraModel = details.cameraModel ?? baseDevice
            lensModel = details.lensModel ?? baseLens
            if let imageSizeMB = details.sizeMB {
                sizeText = String(format: "%.1f MB", imageSizeMB)
            }
        } else if asset.mediaType == .video {
            let details = await loadVideoMetadataDetails(for: asset)
            cameraModel = details.cameraModel ?? baseDevice
            lensModel = details.lensModel ?? baseLens
            if let videoSizeMB = details.sizeMB {
                sizeText = String(format: "%.1f MB", videoSizeMB)
            }
        }

        let dateText = dateFormatter.string(from: asset.creationDate ?? Date())
        let dimensionsText = "\(pixelText) • \(sizeText)"
        let noteText = noteByAssetID[asset.localIdentifier]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        await MainActor.run {
            infoDateText = dateText
            infoFilenameText = filename
            infoDeviceText = cameraModel
            infoLensText = lensModel
            infoDimensionsText = dimensionsText
            infoNoteText = (noteText?.isEmpty == false) ? noteText! : "No note"
        }
    }

    private func loadImageMetadataDetails(for asset: PHAsset) async -> (
        cameraModel: String?, lensModel: String?, sizeMB: Double?
    ) {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                guard let data else {
                    continuation.resume(returning: (nil, nil, nil))
                    return
                }

                let sizeMB = Double(data.count) / 1_048_576.0
                var cameraModel: String?
                var lensModel: String?

                if let source = CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                ),
                    let properties = CGImageSourceCopyPropertiesAtIndex(
                        source,
                        0,
                        nil
                    ) as? [CFString: Any]
                {
                    if let tiff = properties[kCGImagePropertyTIFFDictionary]
                        as? [CFString: Any]
                    {
                        cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
                    }
                    if let exif = properties[kCGImagePropertyExifDictionary]
                        as? [CFString: Any]
                    {
                        lensModel =
                            exif[kCGImagePropertyExifLensModel] as? String
                    }
                }

                continuation.resume(returning: (cameraModel, lensModel, sizeMB))
            }
        }
    }

    private func loadVideoMetadataDetails(for asset: PHAsset) async -> (
        cameraModel: String?, lensModel: String?, sizeMB: Double?
    ) {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: (nil, nil, nil))
                    return
                }

                let common = avAsset?.commonMetadata ?? []
                let make = AVMetadataItem.metadataItems(
                    from: common,
                    filteredByIdentifier: .commonIdentifierMake
                ).first?.stringValue
                let model = AVMetadataItem.metadataItems(
                    from: common,
                    filteredByIdentifier: .commonIdentifierModel
                ).first?.stringValue
                let camera = [make, model].compactMap { $0 }.joined(
                    separator: " "
                )
                let values = try? urlAsset.url.resourceValues(forKeys: [
                    .fileSizeKey
                ])
                let fileSize = values?.fileSize.map { Double($0) / 1_048_576.0 }

                continuation.resume(
                    returning: (
                        camera.isEmpty ? nil : camera, "Video File", fileSize
                    )
                )
            }
        }
    }

    private func saveCurrentNote() {
        guard let id = currentAssetID else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            noteByAssetID.removeValue(forKey: id)
        } else {
            noteByAssetID[id] = trimmed
        }
        saveNotes()
        showNoteSheet = false
    }

    private func deleteCurrentNoteAndClose() {
        guard let id = currentAssetID else { return }
        noteByAssetID.removeValue(forKey: id)
        saveNotes()
        noteDraft = ""
        showNoteSheet = false
    }

    private var noteSheet: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(colorFromHex("000000"))
                .frame(width: 36, height: 5)
                .opacity(0.3)

            HStack {
                if hasSavedNoteForCurrentAsset {
                    Button(action: deleteCurrentNoteAndClose) {
                        Image("app_ic_delete")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                Button(action: { showNoteSheet = false }) {
                    Image("app_ic_close")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            TextField("Enter the note", text: $noteDraft, axis: .vertical)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(colorFromHex("66666D"))
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .lineLimit(1...6)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(colorFromHex("FFFFFF"))
                )
                .shadow(
                    color: colorFromHex("101015", alpha: 0.08),
                    radius: 8,
                    y: 2
                )

            PrimaryActionButton(
                title: "Save",
                isDisabled: false,
                action: saveCurrentNote
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(colorFromHex("FFFFFF", alpha: 0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            colorFromHex("FFFFFF", alpha: 0.45),
                            lineWidth: 1
                        )
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.horizontal, 10)
        .padding(.top, 42)
    }

    private var infoSheet: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(colorFromHex("000000"))
                .frame(width: 36, height: 5)
                .opacity(0.3)

            HStack {
                Color.clear.frame(width: 40, height: 40)
                Spacer()
                Button(action: { showInfoSheet = false }) {
                    Image("app_ic_close")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(infoDateText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorFromHex("101015"))

                Text(infoFilenameText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(colorFromHex("66666D"))

                Divider().overlay(colorFromHex("C8C4DF"))

                Text(infoDeviceText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorFromHex("101015"))

                Text(infoLensText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(colorFromHex("66666D"))

                Text(infoDimensionsText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(colorFromHex("66666D"))

                Divider().overlay(colorFromHex("C8C4DF"))

                Text(infoNoteText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(colorFromHex("66666D"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(colorFromHex("FFFFFF", alpha: 0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            colorFromHex("FFFFFF", alpha: 0.45),
                            lineWidth: 1
                        )
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.horizontal, 10)
        .padding(.top, 42)
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct VideoPlaybackSession: Identifiable {
    let id = UUID()
    let player: AVPlayer
}

private struct MarkedForDeletionView: View {
    let assets: [PHAsset]
    let onClose: () -> Void
    let onUnmark: (String) -> Void
    let onDelete: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image("app_ic_back")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text("Marked to Delete")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colorFromHex("101015"))
                    Text("\(assets.count) items")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(colorFromHex("66666D"))
                }

                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        Button {
                            onUnmark(asset.localIdentifier)
                        } label: {
                            MarkedAssetCell(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 20)
            }

            PrimaryActionButton(
                title: "Delete",
                isDisabled: assets.isEmpty,
                action: onDelete
            )
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
    }
}

private struct MarkedAssetCell: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorFromHex("FFFFFF", alpha: 0.35))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                } else {
                    ProgressView()
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colorFromHex("FFFFFF", alpha: 0.5), lineWidth: 1)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let scale = UIScreen.main.scale
        let target = CGSize(width: 220 * scale, height: 220 * scale)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.deliveryMode = .opportunistic

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            self.image = image
        }
    }
}

private struct DeletionSuccessView: View {
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("app_ic_success")
                .resizable()
                .scaledToFit()
                .frame(height: DeviceTraits.isSmallDevice ? 250 : 316)

            Spacer()

            Text("Success!")
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 26 : 32,
                        weight: .bold
                    )
                )
                .foregroundStyle(colorFromHex("101015"))

            Text("You have cleared the photos.")
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 14 : 16,
                        weight: .regular
                    )
                )
                .foregroundStyle(colorFromHex("66666D"))
                .padding(.top, 6)
                .padding(.bottom, 30)

            PrimaryActionButton(
                title: "Home",
                isDisabled: false,
                action: onHome
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
    }
}

private struct VideoPlayerView: View {
    let player: AVPlayer?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                AVPlayerContainerView(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            }

            Button(action: onClose) {
                Image("app_ic_close")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.trailing, 16)
        }
    }
}

private struct AVPlayerContainerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct GallerySwipeView_Previews: PreviewProvider {
    static var previews: some View {
        GallerySwipeView(kind: .photos, onBack: {})
    }
}
