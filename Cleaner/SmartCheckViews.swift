import Photos
import SwiftUI
import UIKit
import Vision

struct SmartCheckReport: Identifiable {
    let id = UUID()
    let duplicatePhotoIDs: [String]
    let similarPhotoIDs: [String]
    let screenshotIDs: [String]
    let videoIDs: [String]
    let totalPhotos: Int
    let totalVideos: Int

    var duplicatePhotos: Int { duplicatePhotoIDs.count }
    var similarPhotos: Int { similarPhotoIDs.count }
    var screenshots: Int { screenshotIDs.count }
    var videos: Int { videoIDs.count }
}

struct SmartCheckLoadingView: View {
    let onBack: () -> Void
    let onCompleted: (SmartCheckReport) -> Void

    @State private var progress: Double = 0
    @State private var targetProgress: Double = 0
    @State private var didStart = false
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            SmartCheckGlassProgress(progress: progress)

            Spacer()

            Text("Please wait")
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 26 : 32,
                        weight: .bold
                    )
                )
                .foregroundStyle(colorFromHex("101015"))

            Text("Analyzing the gallery for photos and videos.")
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 14 : 16,
                        weight: .regular
                    )
                )
                .foregroundStyle(colorFromHex("66666D"))
                .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .task {
            startSmoothLoading()
        }
        .onDisappear {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }

    private func startSmoothLoading() {
        guard !didStart else { return }
        didStart = true
        progress = 0
        targetProgress = 0
        loadingTask?.cancel()

        loadingTask = Task {
            let startedAt = Date()
            let minimumDuration: TimeInterval = 3.0
            var completedReport: SmartCheckReport?
            var analysisFinished = false

            let analysisTask = Task {
                let report = await SmartCheckAnalyzer.analyze { value in
                    Task { @MainActor in
                        targetProgress = min(value, 0.97)
                    }
                }
                await MainActor.run {
                    completedReport = report
                    analysisFinished = true
                }
            }

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let timeDriven = min(elapsed / minimumDuration, 0.97)
                let isDone = await MainActor.run { analysisFinished }

                await MainActor.run {
                    let desired = max(timeDriven, targetProgress)
                    let stepPerFrame = 0.008
                    if desired > progress {
                        progress = min(progress + stepPerFrame, desired, 0.97)
                    } else {
                        progress = min(progress, 0.97)
                    }
                }

                if isDone && elapsed >= minimumDuration {
                    break
                }

                try? await Task.sleep(
                    nanoseconds: UInt64((1.0 / 60.0) * 1_000_000_000)
                )
            }

            guard !Task.isCancelled else { return }
            _ = await analysisTask.result
            let report = await MainActor.run { completedReport }
            guard let report else { return }

            await MainActor.run {
                withAnimation(.linear(duration: 0.22)) {
                    progress = 1
                }
            }
            try? await Task.sleep(nanoseconds: 220_000_000)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                onCompleted(report)
            }
        }
    }
}

struct SmartCheckResultView: View {
    let report: SmartCheckReport
    let onBack: () -> Void
    @State private var openedCategoryRoute: SmartCheckCategoryRoute?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image("app_ic_back")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Smart Check")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(colorFromHex("101015"))

                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(percent)%")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(colorFromHex("101015"))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colorFromHex("B7C5F4"))
                            .frame(height: 24)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        colorFromHex("3873E9"),
                                        colorFromHex("4D4FE5"),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(
                                    (proxy.size.width - 16)
                                        * (Double(percent) / 100),
                                    0
                                ),
                                height: 16
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                .frame(height: 30)
            }
            .padding(.horizontal, 22)

            HStack {
                VStack(spacing: 2) {
                    Text("Photos")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colorFromHex("101015"))
                    Text("\(photoPercent)%")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(colorFromHex("66666D"))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("Video")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colorFromHex("101015"))
                    Text("\(videoPercent)%")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(colorFromHex("66666D"))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .frame(height: 62)
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
            .padding(.horizontal, 22)
            .padding(.top, 16)

            Spacer()

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ],
                spacing: 16
            ) {
                Button(action: {
                    openedCategoryRoute = SmartCheckCategoryRoute(
                        kind: .photos,
                        title: "Duplicate Photos",
                        assetIDs: report.duplicatePhotoIDs
                    )
                }) {
                    SmartCheckTileView(
                        imageName: "app_ic_photo",
                        title: "Duplicate Photos",
                        subtitle: "\(report.duplicatePhotos) Items"
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    openedCategoryRoute = SmartCheckCategoryRoute(
                        kind: .photos,
                        title: "Similar Photo",
                        assetIDs: report.similarPhotoIDs
                    )
                }) {
                    SmartCheckTileView(
                        imageName: "app_ic_similar",
                        title: "Similar Photo",
                        subtitle: "\(report.similarPhotos) Items"
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    openedCategoryRoute = SmartCheckCategoryRoute(
                        kind: .photos,
                        title: "Screenshots",
                        assetIDs: report.screenshotIDs
                    )
                }) {
                    SmartCheckTileView(
                        imageName: "app_ic_scr",
                        title: "Screenshots",
                        subtitle: "\(report.screenshots) Items"
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    openedCategoryRoute = SmartCheckCategoryRoute(
                        kind: .videos,
                        title: "Video",
                        assetIDs: report.videoIDs
                    )
                }) {
                    SmartCheckTileView(
                        imageName: "app_ic_video",
                        title: "Video",
                        subtitle: "\(report.videos) Items"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .fullScreenCover(item: $openedCategoryRoute) { route in
            GallerySwipeView(
                kind: route.kind,
                onBack: { openedCategoryRoute = nil },
                titleOverride: route.title,
                assetIDs: route.assetIDs
            )
        }
    }

    private var percent: Int {
        let issues =
            report.duplicatePhotos + report.similarPhotos + report.screenshots
            + report.videos
        let all = max(report.totalPhotos + report.totalVideos, 1)
        return min(max(Int((Double(issues) / Double(all)) * 100), 1), 99)
    }

    private var photoPercent: Int {
        let all = max(report.totalPhotos + report.totalVideos, 1)
        return Int((Double(report.totalPhotos) / Double(all) * 100).rounded())
    }

    private var videoPercent: Int {
        max(0, 100 - photoPercent)
    }
}

private struct SmartCheckCategoryRoute: Identifiable {
    let id = UUID()
    let kind: GallerySwipeView.MediaKind
    let title: String
    let assetIDs: [String]
}

private struct SmartCheckGlassProgress: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(colorFromHex("DDE5F3", alpha: 0.82))
                .frame(width: 332, height: 332)
                .overlay(
                    Circle()
                        .stroke(
                            colorFromHex("FFFFFF", alpha: 0.55),
                            lineWidth: 2
                        )
                )
                .shadow(
                    color: colorFromHex("FFFFFF", alpha: 0.30),
                    radius: 3,
                    x: -1,
                    y: -1
                )
                .shadow(
                    color: colorFromHex("8EA8D9", alpha: 0.18),
                    radius: 12,
                    y: 8
                )

            Circle()
                .stroke(colorFromHex("AEC3EC", alpha: 0.95), lineWidth: 30)
                .frame(width: 286, height: 286)
                .shadow(
                    color: colorFromHex("789AD7", alpha: 0.12),
                    radius: 4,
                    y: 2
                )

            Circle()
                .trim(from: 0.001, to: max(progress, 0.001))
                .stroke(
                    LinearGradient(
                        colors: [
                            colorFromHex("3A70E8"), colorFromHex("2D95F2"),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 260, height: 260)
                .shadow(
                    color: colorFromHex("3873E9", alpha: 0.20),
                    radius: 4,
                    y: 1
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            colorFromHex("9AC1ED"), colorFromHex("92B8E8"),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 218, height: 218)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorFromHex("FFFFFF", alpha: 0.16),
                                    colorFromHex("FFFFFF", alpha: 0.00),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            colorFromHex("FFFFFF", alpha: 0.24),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: colorFromHex("6D90C7", alpha: 0.18),
                    radius: 7,
                    y: 4
                )

            Text("\(Int(progress * 100))%")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(colorFromHex("FFFFFF"))
                .shadow(
                    color: colorFromHex("000000", alpha: 0.12),
                    radius: 1,
                    y: 1
                )
        }
    }
}

private struct SmartCheckTileView: View {
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

            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(colorFromHex("66666D"))

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

enum SmartCheckAnalyzer {
    private struct AnalysisSample {
        let id: String
        let width: Int
        let height: Int
        let creationDate: Date?
        let dHash: UInt64?
        let aHash: UInt64?
        let feature: VNFeaturePrintObservation?
    }

    private struct UnionFind {
        var parent: [Int]
        var rank: [Int]

        init(count: Int) {
            parent = Array(0..<count)
            rank = Array(repeating: 0, count: count)
        }

        mutating func find(_ index: Int) -> Int {
            if parent[index] == index { return index }
            parent[index] = find(parent[index])
            return parent[index]
        }

        mutating func union(_ lhs: Int, _ rhs: Int) {
            let rootL = find(lhs)
            let rootR = find(rhs)
            if rootL == rootR { return }

            if rank[rootL] < rank[rootR] {
                parent[rootL] = rootR
            } else if rank[rootL] > rank[rootR] {
                parent[rootR] = rootL
            } else {
                parent[rootR] = rootL
                rank[rootL] += 1
            }
        }
    }

    static func analyze(progress: @escaping @Sendable (Double) -> Void) async
        -> SmartCheckReport
    {
        await Task.detached(priority: .userInitiated) {
            let photos = fetchAssets(type: .image)
            let videos = fetchAssets(type: .video)
            var processed = 0
            let totalSteps = max(photos.count + 24, 30)

            var samples: [AnalysisSample] = []
            samples.reserveCapacity(photos.count)

            for asset in photos {
                let image = await loadImageForAnalysis(asset: asset)
                let cgImage = image?.cgImage

                samples.append(
                    AnalysisSample(
                        id: asset.localIdentifier,
                        width: asset.pixelWidth,
                        height: asset.pixelHeight,
                        creationDate: asset.creationDate,
                        dHash: differenceHash(from: cgImage),
                        aHash: averageHash(from: cgImage),
                        feature: featurePrint(from: cgImage)
                    )
                )

                processed += 1
                progress(min(Double(processed) / Double(totalSteps), 0.55))
            }

            let duplicateIDs = detectDuplicateIDs(samples: samples) { local in
                progress(0.55 + local * 0.22)
            }

            let similarIDs = detectSimilarIDs(
                samples: samples,
                excluding: duplicateIDs
            ) { local in
                progress(0.77 + local * 0.20)
            }

            let screenshotIDs = fetchScreenshotIDs()
            let report = SmartCheckReport(
                duplicatePhotoIDs: sortedIDs(duplicateIDs, from: samples),
                similarPhotoIDs: sortedIDs(similarIDs, from: samples),
                screenshotIDs: screenshotIDs,
                videoIDs: videos.map(\.localIdentifier),
                totalPhotos: photos.count,
                totalVideos: videos.count
            )

            progress(1)
            return report
        }.value
    }

    private static func detectDuplicateIDs(
        samples: [AnalysisSample],
        progress: @escaping (Double) -> Void
    ) -> Set<String> {
        let candidates = samples.filter { $0.dHash != nil && $0.aHash != nil }
        let groups = Dictionary(grouping: candidates) { sample in
            "\(sample.width)x\(sample.height)"
        }

        var duplicates = Set<String>()
        var completedGroups = 0
        let groupsCount = max(groups.count, 1)

        for group in groups.values {
            defer {
                completedGroups += 1
                progress(Double(completedGroups) / Double(groupsCount))
            }

            if group.count <= 1 { continue }

            var uf = UnionFind(count: group.count)
            let orderedIndexes = group.indices.sorted {
                (group[$0].dHash ?? 0) < (group[$1].dHash ?? 0)
            }

            for orderedIndex in orderedIndexes.indices {
                let lhsIndex = orderedIndexes[orderedIndex]
                guard let lhsDHash = group[lhsIndex].dHash,
                    let lhsAHash = group[lhsIndex].aHash
                else {
                    continue
                }

                let maxCheck = min(orderedIndex + 48, orderedIndexes.count - 1)
                if orderedIndex >= maxCheck { continue }

                for nextIndex in (orderedIndex + 1)...maxCheck {
                    let rhsIndex = orderedIndexes[nextIndex]
                    guard let rhsDHash = group[rhsIndex].dHash,
                        let rhsAHash = group[rhsIndex].aHash
                    else {
                        continue
                    }

                    let dDistance = hammingDistance(lhsDHash, rhsDHash)
                    let aDistance = hammingDistance(lhsAHash, rhsAHash)

                    if dDistance > 6 || aDistance > 6 { continue }

                    let featureDistanceValue = featureDistance(
                        group[lhsIndex].feature,
                        group[rhsIndex].feature
                    )
                    let shouldUnion =
                        (featureDistanceValue != nil
                            && featureDistanceValue! <= 0.06)
                        || (featureDistanceValue == nil && dDistance <= 3
                            && aDistance <= 3)

                    if shouldUnion {
                        uf.union(lhsIndex, rhsIndex)
                    }
                }
            }

            var components: [Int: [Int]] = [:]
            for index in group.indices {
                components[uf.find(index), default: []].append(index)
            }

            for component in components.values where component.count > 1 {
                let keepIndex =
                    component.min { lhs, rhs in
                        let lhsDate = group[lhs].creationDate ?? .distantPast
                        let rhsDate = group[rhs].creationDate ?? .distantPast
                        return lhsDate < rhsDate
                    } ?? component[0]

                for index in component where index != keepIndex {
                    duplicates.insert(group[index].id)
                }
            }
        }

        return duplicates
    }

    private static func detectSimilarIDs(
        samples: [AnalysisSample],
        excluding duplicateIDs: Set<String>,
        progress: @escaping (Double) -> Void
    ) -> Set<String> {
        let candidates = samples.filter {
            !duplicateIDs.contains($0.id)
                && $0.feature != nil
                && $0.dHash != nil
                && $0.aHash != nil
        }
        let groups = Dictionary(grouping: candidates) { sample in
            let ratio =
                sample.height > 0
                ? Int(
                    ((Double(sample.width) / Double(sample.height)) * 10)
                        .rounded()
                )
                : 0
            let orientation = sample.width >= sample.height ? "L" : "P"
            return "\(orientation)-\(ratio)"
        }

        var similar = Set<String>()
        var completedGroups = 0
        let groupsCount = max(groups.count, 1)

        for group in groups.values {
            defer {
                completedGroups += 1
                progress(Double(completedGroups) / Double(groupsCount))
            }

            if group.count <= 1 { continue }

            let sorted = group.sorted { lhs, rhs in
                let lhsDate = lhs.creationDate ?? .distantPast
                let rhsDate = rhs.creationDate ?? .distantPast
                return lhsDate < rhsDate
            }

            let fullCompare = sorted.count <= 220

            for i in sorted.indices {
                let maxIndex =
                    fullCompare
                    ? (sorted.count - 1)
                    : min(i + 120, sorted.count - 1)
                if i >= maxIndex { continue }

                guard let lhsDHash = sorted[i].dHash,
                    let lhsAHash = sorted[i].aHash
                else {
                    continue
                }

                for j in (i + 1)...maxIndex {
                    guard let rhsDHash = sorted[j].dHash,
                        let rhsAHash = sorted[j].aHash
                    else {
                        continue
                    }

                    let dDistance = hammingDistance(lhsDHash, rhsDHash)
                    let aDistance = hammingDistance(lhsAHash, rhsAHash)
                    if dDistance <= 6 && aDistance <= 6 { continue }
                    if dDistance > 28 && aDistance > 30 { continue }

                    if !fullCompare,
                        let lhsDate = sorted[i].creationDate,
                        let rhsDate = sorted[j].creationDate
                    {
                        let delta = abs(lhsDate.timeIntervalSince(rhsDate))
                        if delta > 7 * 24 * 3600 && dDistance > 16
                            && aDistance > 18
                        {
                            continue
                        }
                    }

                    guard
                        let distance = featureDistance(
                            sorted[i].feature,
                            sorted[j].feature
                        )
                    else {
                        continue
                    }

                    if distance <= 0.14 {
                        similar.insert(sorted[i].id)
                        similar.insert(sorted[j].id)
                    }
                }
            }
        }

        return similar
    }

    private static func sortedIDs(
        _ ids: Set<String>,
        from samples: [AnalysisSample]
    ) -> [String] {
        let dateMap = Dictionary(
            uniqueKeysWithValues: samples.map {
                ($0.id, $0.creationDate ?? .distantPast)
            }
        )
        return ids.sorted { lhs, rhs in
            (dateMap[lhs] ?? .distantPast) < (dateMap[rhs] ?? .distantPast)
        }
    }

    private static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    private static func featureDistance(
        _ lhs: VNFeaturePrintObservation?,
        _ rhs: VNFeaturePrintObservation?
    ) -> Float? {
        guard let lhs, let rhs else { return nil }
        var distance: Float = .greatestFiniteMagnitude
        do {
            try lhs.computeDistance(&distance, to: rhs)
            return distance
        } catch {
            return nil
        }
    }

    private static func fetchAssets(type: PHAssetMediaType) -> [PHAsset] {
        let result = PHAsset.fetchAssets(with: type, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private static func fetchScreenshotIDs() -> [String] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtype & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let result = PHAsset.fetchAssets(with: options)
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    private static func loadImageForAnalysis(asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func differenceHash(from cgImage: CGImage?) -> UInt64? {
        guard let cgImage else { return nil }

        let width = 9
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let left = pixels[y * width + x]
                let right = pixels[y * width + x + 1]
                hash <<= 1
                if left > right {
                    hash |= 1
                }
            }
        }
        return hash
    }

    private static func averageHash(from cgImage: CGImage?) -> UInt64? {
        guard let cgImage else { return nil }

        let width = 8
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        let average = pixels.reduce(0, { $0 + Int($1) }) / pixels.count
        var hash: UInt64 = 0
        for pixel in pixels {
            hash <<= 1
            if Int(pixel) >= average {
                hash |= 1
            }
        }
        return hash
    }

    private static func featurePrint(from cgImage: CGImage?)
        -> VNFeaturePrintObservation?
    {
        guard let cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }
}

struct SmartCheckLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        SmartCheckLoadingView(onBack: {}, onCompleted: { _ in })
    }
}

struct SmartCheckResultView_Previews: PreviewProvider {
    static var previews: some View {
        SmartCheckResultView(
            report: SmartCheckReport(
                duplicatePhotoIDs: Array(
                    repeating: UUID().uuidString,
                    count: 10
                ),
                similarPhotoIDs: Array(repeating: UUID().uuidString, count: 25),
                screenshotIDs: Array(repeating: UUID().uuidString, count: 100),
                videoIDs: Array(repeating: UUID().uuidString, count: 25),
                totalPhotos: 140,
                totalVideos: 60
            ),
            onBack: {}
        )
    }
}
