@preconcurrency import Photos
import SwiftUI
import UIKit
import Vision
import os

private let smartCheckLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Cleaner",
    category: "SmartCheck"
)

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

    private let largeLibraryThreshold = 5000

    @State private var progress: Double = 0
    @State private var targetProgress: Double = 0
    @State private var didStart = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var primaryMessage =
        "Analyzing the gallery for photos and videos."
    @State private var cautionMessage =
        "Please keep the app open until Smart Check is complete."

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

            Text(primaryMessage)
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 14 : 16,
                        weight: .regular
                    )
                )
                .foregroundStyle(colorFromHex("66666D"))
                .padding(.top, 6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Text(cautionMessage)
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 13 : 14,
                        weight: .medium
                    )
                )
                .foregroundStyle(colorFromHex("D94848"))
                .padding(.top, 10)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

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
        smartCheckLogger.info("Smart Check loading started")
        didStart = true
        progress = 0
        targetProgress = 0
        primaryMessage = "Analyzing the gallery for photos and videos."
        cautionMessage = "Please keep the app open until Smart Check is complete."
        loadingTask?.cancel()

        let photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
        if photoCount >= largeLibraryThreshold {
            primaryMessage =
                "You have \(photoCount) photos. Smart Check analysis may take longer."
            smartCheckLogger.info(
                "Large library detected photos=\(photoCount, privacy: .public)"
            )
        }

        loadingTask = Task {
            let startedAt = Date()
            let minimumLoadingDuration: TimeInterval = 2.0
            var completedReport: SmartCheckReport?
            var analysisFinished = false
            var lastWaitingLogAt = Date.distantPast

            let analysisTask = Task {
                let report = await SmartCheckAnalyzer.analyze { value in
                    Task { @MainActor in
                        targetProgress = max(0, min(value, 1))
                    }
                }
                await MainActor.run {
                    completedReport = report
                    analysisFinished = true
                }
                smartCheckLogger.info(
                    "Smart Check analyzer finished duplicates=\(report.duplicatePhotos, privacy: .public) similar=\(report.similarPhotos, privacy: .public) screenshots=\(report.screenshots, privacy: .public) videos=\(report.videos, privacy: .public)"
                )
            }

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let snapshot = await MainActor.run {
                    (
                        analysisFinished,
                        targetProgress,
                        progress
                    )
                }
                let isDone = snapshot.0
                let minimumReached = elapsed >= minimumLoadingDuration

                await MainActor.run {
                    let desired = minimumReached
                        ? snapshot.1
                        : min(snapshot.1, 0.99)
                    let stepPerFrame = 0.012
                    if desired > progress {
                        progress = min(progress + stepPerFrame, desired)
                    } else {
                        progress = min(progress, desired)
                    }
                }

                if !isDone && snapshot.1 >= 0.99
                    && Date().timeIntervalSince(lastWaitingLogAt) >= 2.0
                {
                    smartCheckLogger.info(
                        "Smart Check waiting near completion currentProgress=\(Int(snapshot.2 * 100), privacy: .public)% elapsed=\(Int(elapsed), privacy: .public)s"
                    )
                    lastWaitingLogAt = Date()
                }

                if isDone && minimumReached {
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
                withAnimation(.linear(duration: 0.12)) {
                    progress = 1
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                onCompleted(report)
            }
            let totalElapsed = Date().timeIntervalSince(startedAt)
            smartCheckLogger.info(
                "Smart Check loading completed totalElapsed=\(Int(totalElapsed), privacy: .public)s"
            )
        }
    }
}

struct SmartCheckFlowView: View {
    let onClose: () -> Void

    @State private var report: SmartCheckReport?

    var body: some View {
        Group {
            if let report {
                SmartCheckResultView(
                    report: report,
                    onBack: onClose
                )
            } else {
                SmartCheckLoadingView(
                    onBack: onClose,
                    onCompleted: { finishedReport in
                        report = finishedReport
                    }
                )
            }
        }
        .transaction { transaction in
            transaction.animation = nil
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
        let rawPercent = Int(
            (Double(issues) / Double(all) * 100).rounded()
        )
        return min(max(rawPercent, 0), 100)
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
    private static let sampleProgressStride = 100
    private static let cacheRestoreLogStride = 1000
    private static let sampleCacheCheckpointStride = 1000
    private static let maxWorkerCap = 12
    private static let imageTargetSize = CGSize(width: 512, height: 512)
    private static let imageManager = PHCachingImageManager()
    private static let sampleCacheVersion = 1
    private static let sampleCacheFileName = "smart_check_samples_v1.plist"

    private enum WorkerStage: String {
        case sampling
        case grouping
    }

    private static func workerLimit(
        for stage: WorkerStage,
        workItems: Int
    ) -> Int {
        let processInfo = ProcessInfo.processInfo
        let cores = max(processInfo.activeProcessorCount, 2)
        let memoryGB = Double(processInfo.physicalMemory)
            / Double(1024 * 1024 * 1024)

        var workers = cores * 2
        if memoryGB <= 3 {
            workers = min(workers, 3)
        } else if memoryGB <= 4 {
            workers = min(workers, 4)
        } else if memoryGB <= 6 {
            workers = min(workers, 6)
        } else if memoryGB <= 8 {
            workers = min(workers, 8)
        } else if memoryGB <= 12 {
            workers = min(workers, 10)
        } else {
            workers = min(workers, maxWorkerCap)
        }

        if stage == .grouping {
            workers = max(2, Int((Double(workers) * 0.75).rounded(.down)))
        }

        if processInfo.isLowPowerModeEnabled {
            if stage == .sampling {
                let floor = workItems >= 10_000 ? 5 : 4
                workers = max(
                    floor,
                    Int((Double(workers) * 0.85).rounded(.toNearestOrAwayFromZero))
                )
            } else {
                workers = max(2, workers / 2)
            }
        }

        if stage == .sampling
            && processInfo.thermalState == .nominal
            && workItems >= 10_000
        {
            workers = min(workers + 1, maxWorkerCap)
        }

        switch processInfo.thermalState {
        case .nominal:
            break
        case .fair:
            workers = max(2, workers - 1)
        case .serious, .critical:
            workers = max(2, workers / 2)
        @unknown default:
            workers = max(2, workers / 2)
        }

        return max(2, min(workers, maxWorkerCap))
    }

    private static func workerProfileDescription(
        stage: WorkerStage,
        workers: Int,
        workItems: Int
    ) -> String {
        let processInfo = ProcessInfo.processInfo
        let cores = max(processInfo.activeProcessorCount, 2)
        let memoryGB = Int(
            (Double(processInfo.physicalMemory) / Double(1024 * 1024 * 1024))
                .rounded(.down)
        )
        return
            "stage=\(stage.rawValue) workers=\(workers) items=\(workItems) cores=\(cores) memoryGB=\(memoryGB) lowPower=\(processInfo.isLowPowerModeEnabled) thermal=\(String(describing: processInfo.thermalState))"
    }

    private struct AnalysisSample: @unchecked Sendable {
        let id: String
        let width: Int
        let height: Int
        let creationDate: Date?
        let dHash: UInt64?
        let aHash: UInt64?
        let feature: VNFeaturePrintObservation?
    }

    private struct SampleTaskResult {
        let index: Int
        let sample: AnalysisSample
        let missingImage: Bool
        let slowLoad: Bool
        let cacheRecord: CachedSampleRecord?
    }

    private struct SampleBuildResult {
        let samples: [AnalysisSample]
        let missingImageCount: Int
        let slowImageLoadCount: Int
        let cacheHitCount: Int
        let cachedWriteCount: Int
    }

    private struct SampleCacheSnapshot: Codable {
        let version: Int
        let generatedAt: Date
        let imageTargetWidth: Int
        let imageTargetHeight: Int
        let entries: [String: CachedSampleRecord]
    }

    private struct CachedSampleRecord: Codable {
        let id: String
        let fingerprint: String
        let width: Int
        let height: Int
        let creationDate: Date?
        let dHash: UInt64?
        let aHash: UInt64?
        let featureArchive: Data?
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
            let startedAt = Date()
            smartCheckLogger.info("Analyzer stage started")
            let photos = fetchAssets(type: .image)
            let videos = fetchAssets(type: .video)
            smartCheckLogger.info(
                "Assets fetched photos=\(photos.count, privacy: .public) videos=\(videos.count, privacy: .public)"
            )
            let cacheEntries = loadSampleCache()
            smartCheckLogger.info(
                "Sample cache loaded entries=\(cacheEntries.count, privacy: .public)"
            )
            let samplingStartedAt = Date()
            let sampleBuildResult = await buildSamples(
                from: photos,
                cachedEntries: cacheEntries,
                progress: progress
            )
            let samples = sampleBuildResult.samples
            let missingImageCount = sampleBuildResult.missingImageCount
            let slowImageLoadCount = sampleBuildResult.slowImageLoadCount
            let samplingElapsed = Date().timeIntervalSince(samplingStartedAt)

            smartCheckLogger.info(
                "Sampling finished samples=\(samples.count, privacy: .public) cacheHits=\(sampleBuildResult.cacheHitCount, privacy: .public) cacheWrites=\(sampleBuildResult.cachedWriteCount, privacy: .public) missingImages=\(missingImageCount, privacy: .public) slowLoads=\(slowImageLoadCount, privacy: .public) elapsed=\(Int(samplingElapsed), privacy: .public)s"
            )

            let duplicateStartedAt = Date()
            let duplicateIDs = await detectDuplicateIDs(samples: samples) { local in
                progress(0.55 + local * 0.22)
            }
            progress(0.77)
            let duplicateElapsed = Date().timeIntervalSince(duplicateStartedAt)
            smartCheckLogger.info(
                "Duplicate stage finished duplicates=\(duplicateIDs.count, privacy: .public) elapsed=\(Int(duplicateElapsed), privacy: .public)s"
            )

            let similarStartedAt = Date()
            let similarIDs = await detectSimilarIDs(
                samples: samples,
                excluding: duplicateIDs
            ) { local in
                progress(0.77 + local * 0.20)
            }
            progress(0.97)
            let similarElapsed = Date().timeIntervalSince(similarStartedAt)
            smartCheckLogger.info(
                "Similar stage finished similar=\(similarIDs.count, privacy: .public) elapsed=\(Int(similarElapsed), privacy: .public)s"
            )

            let screenshotsStartedAt = Date()
            let screenshotIDs = fetchScreenshotIDs { local in
                progress(0.97 + local * 0.03)
            }
            let screenshotsElapsed = Date().timeIntervalSince(screenshotsStartedAt)
            smartCheckLogger.info(
                "Screenshot stage finished screenshots=\(screenshotIDs.count, privacy: .public) elapsed=\(Int(screenshotsElapsed), privacy: .public)s"
            )

            let report = SmartCheckReport(
                duplicatePhotoIDs: sortedIDs(duplicateIDs, from: samples),
                similarPhotoIDs: sortedIDs(similarIDs, from: samples),
                screenshotIDs: screenshotIDs,
                videoIDs: videos.map(\.localIdentifier),
                totalPhotos: photos.count,
                totalVideos: videos.count
            )

            progress(1)
            let totalElapsed = Date().timeIntervalSince(startedAt)
            smartCheckLogger.info(
                "Analyzer stage completed totalElapsed=\(Int(totalElapsed), privacy: .public)s"
            )
            return report
        }.value
    }

    private static func detectDuplicateIDs(
        samples: [AnalysisSample],
        progress: @escaping (Double) -> Void
    ) async -> Set<String> {
        let candidates = samples.filter { $0.dHash != nil && $0.aHash != nil }
        let groups = Dictionary(grouping: candidates) { sample in
            "\(sample.width)x\(sample.height)"
        }
        let groupList = Array(groups.values)
        let maxGroupSize = groups.values.map(\.count).max() ?? 0
        smartCheckLogger.info(
            "Duplicate stage started candidates=\(candidates.count, privacy: .public) groups=\(groups.count, privacy: .public) maxGroupSize=\(maxGroupSize, privacy: .public)"
        )

        var duplicates = Set<String>()
        var completedGroups = 0
        let groupsCount = max(groupList.count, 1)
        var lastLoggedStep = -1

        guard !groupList.isEmpty else {
            progress(1)
            return duplicates
        }

        let workers = min(
            workerLimit(for: .grouping, workItems: groupList.count),
            groupList.count
        )
        smartCheckLogger.info(
            "Duplicate stage \(workerProfileDescription(stage: .grouping, workers: workers, workItems: groupList.count), privacy: .public)"
        )

        await withTaskGroup(of: Set<String>.self) { group in
            var nextIndex = 0

            func enqueueTask(index: Int, into group: inout TaskGroup<Set<String>>) {
                let localGroup = groupList[index]
                group.addTask {
                    duplicateIDs(in: localGroup)
                }
            }

            let initialCount = min(workers, groupList.count)
            for _ in 0..<initialCount {
                enqueueTask(index: nextIndex, into: &group)
                nextIndex += 1
            }

            while let groupDuplicates = await group.next() {
                duplicates.formUnion(groupDuplicates)
                completedGroups += 1
                progress(Double(completedGroups) / Double(groupsCount))
                let step = Int(
                    (Double(completedGroups) / Double(groupsCount)) * 10
                )
                if step > lastLoggedStep {
                    lastLoggedStep = step
                    smartCheckLogger.info(
                        "Duplicate stage progress=\(min(step * 10, 100), privacy: .public)% groups=\(completedGroups, privacy: .public)/\(groupsCount, privacy: .public)"
                    )
                }

                if nextIndex < groupList.count {
                    enqueueTask(index: nextIndex, into: &group)
                    nextIndex += 1
                }
            }
        }

        smartCheckLogger.info(
            "Duplicate stage result duplicates=\(duplicates.count, privacy: .public)"
        )
        return duplicates
    }

    private static func detectSimilarIDs(
        samples: [AnalysisSample],
        excluding duplicateIDs: Set<String>,
        progress: @escaping (Double) -> Void
    ) async -> Set<String> {
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
        let groupList = Array(groups.values)
        let maxGroupSize = groups.values.map(\.count).max() ?? 0
        smartCheckLogger.info(
            "Similar stage started candidates=\(candidates.count, privacy: .public) groups=\(groups.count, privacy: .public) maxGroupSize=\(maxGroupSize, privacy: .public)"
        )

        var similar = Set<String>()
        var completedGroups = 0
        let groupsCount = max(groupList.count, 1)
        var lastLoggedStep = -1

        guard !groupList.isEmpty else {
            progress(1)
            return similar
        }

        let workers = min(
            workerLimit(for: .grouping, workItems: groupList.count),
            groupList.count
        )
        smartCheckLogger.info(
            "Similar stage \(workerProfileDescription(stage: .grouping, workers: workers, workItems: groupList.count), privacy: .public)"
        )

        await withTaskGroup(of: Set<String>.self) { group in
            var nextIndex = 0

            func enqueueTask(index: Int, into group: inout TaskGroup<Set<String>>) {
                let localGroup = groupList[index]
                group.addTask {
                    similarIDs(in: localGroup)
                }
            }

            let initialCount = min(workers, groupList.count)
            for _ in 0..<initialCount {
                enqueueTask(index: nextIndex, into: &group)
                nextIndex += 1
            }

            while let groupSimilar = await group.next() {
                similar.formUnion(groupSimilar)
                completedGroups += 1
                progress(Double(completedGroups) / Double(groupsCount))
                let step = Int(
                    (Double(completedGroups) / Double(groupsCount)) * 10
                )
                if step > lastLoggedStep {
                    lastLoggedStep = step
                    smartCheckLogger.info(
                        "Similar stage progress=\(min(step * 10, 100), privacy: .public)% groups=\(completedGroups, privacy: .public)/\(groupsCount, privacy: .public)"
                    )
                }

                if nextIndex < groupList.count {
                    enqueueTask(index: nextIndex, into: &group)
                    nextIndex += 1
                }
            }
        }

        smartCheckLogger.info(
            "Similar stage result similar=\(similar.count, privacy: .public)"
        )
        return similar
    }

    private static func duplicateIDs(in group: [AnalysisSample]) -> Set<String> {
        guard group.count > 1 else { return [] }

        var duplicates = Set<String>()
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

        return duplicates
    }

    private static func similarIDs(in group: [AnalysisSample]) -> Set<String> {
        guard group.count > 1 else { return [] }

        var similar = Set<String>()
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

        return similar
    }

    private static func buildSamples(
        from photos: [PHAsset],
        cachedEntries: [String: CachedSampleRecord],
        progress: @escaping @Sendable (Double) -> Void
    ) async -> SampleBuildResult {
        guard !photos.isEmpty else {
            progress(0.55)
            return SampleBuildResult(
                samples: [],
                missingImageCount: 0,
                slowImageLoadCount: 0,
                cacheHitCount: 0,
                cachedWriteCount: 0
            )
        }

        let workers = min(
            workerLimit(for: .sampling, workItems: photos.count),
            photos.count
        )
        smartCheckLogger.info(
            "Sampling stage started photos=\(photos.count, privacy: .public) \(workerProfileDescription(stage: .sampling, workers: workers, workItems: photos.count), privacy: .public)"
        )

        let photoIDs = Set(photos.map(\.localIdentifier))
        var cacheEntries = cachedEntries.filter { photoIDs.contains($0.key) }
        var cachePruned = cacheEntries.count != cachedEntries.count
        var processed = 0
        var cacheHitCount = 0
        var cachedWriteCount = 0
        var dirtyCacheWrites = 0
        var missingImageCount = 0
        var slowImageLoadCount = 0
        var orderedSamples = Array<AnalysisSample?>(repeating: nil, count: photos.count)
        var pendingIndexes: [Int] = []

        for index in photos.indices {
            let asset = photos[index]
            let fingerprint = assetFingerprint(for: asset)
            if let record = cacheEntries[asset.localIdentifier],
                record.fingerprint == fingerprint
            {
                if let sample = sampleFromCache(record) {
                    orderedSamples[index] = sample
                    cacheHitCount += 1
                    processed += 1
                    let samplingLocal = Double(processed) / Double(photos.count)
                    progress(min(samplingLocal * 0.55, 0.55))
                    if processed == photos.count
                        || processed % cacheRestoreLogStride == 0
                    {
                        smartCheckLogger.info(
                            "Sampling cache restore processed=\(processed, privacy: .public)/\(photos.count, privacy: .public)"
                        )
                    }
                } else {
                    cacheEntries.removeValue(forKey: asset.localIdentifier)
                    cachePruned = true
                    pendingIndexes.append(index)
                }
            } else {
                pendingIndexes.append(index)
            }
        }

        smartCheckLogger.info(
            "Sampling cache reuse hits=\(cacheHitCount, privacy: .public) pending=\(pendingIndexes.count, privacy: .public)"
        )
        let pendingTotal = pendingIndexes.count
        var pendingProcessed = 0
        let pendingStartedAt = Date()

        await withTaskGroup(of: SampleTaskResult.self) { group in
            var nextIndex = 0

            func enqueueTask(index: Int, into group: inout TaskGroup<SampleTaskResult>) {
                let photoIndex = pendingIndexes[index]
                let asset = photos[photoIndex]
                group.addTask {
                    let loadStartedAt = Date()
                    let image = await loadImageForAnalysis(asset: asset)
                    let loadElapsed = Date().timeIntervalSince(loadStartedAt)
                    let cgImage = image?.cgImage

                    let sample = AnalysisSample(
                        id: asset.localIdentifier,
                        width: asset.pixelWidth,
                        height: asset.pixelHeight,
                        creationDate: asset.creationDate,
                        dHash: differenceHash(from: cgImage),
                        aHash: averageHash(from: cgImage),
                        feature: featurePrint(from: cgImage)
                    )

                    return SampleTaskResult(
                        index: photoIndex,
                        sample: sample,
                        missingImage: cgImage == nil,
                        slowLoad: loadElapsed > 1.5,
                        cacheRecord: cacheRecord(
                            from: sample,
                            fingerprint: assetFingerprint(for: asset)
                        )
                    )
                }
            }

            let initialCount = min(workers, pendingIndexes.count)
            for _ in 0..<initialCount {
                enqueueTask(index: nextIndex, into: &group)
                nextIndex += 1
            }

            while let result = await group.next() {
                orderedSamples[result.index] = result.sample
                processed += 1
                pendingProcessed += 1
                if result.missingImage {
                    missingImageCount += 1
                }
                if result.slowLoad {
                    slowImageLoadCount += 1
                }
                if let cacheRecord = result.cacheRecord {
                    cacheEntries[cacheRecord.id] = cacheRecord
                    cachedWriteCount += 1
                    dirtyCacheWrites += 1
                    if dirtyCacheWrites >= sampleCacheCheckpointStride {
                        saveSampleCache(cacheEntries, reason: "checkpoint")
                        dirtyCacheWrites = 0
                    }
                }

                let samplingLocal = Double(processed) / Double(photos.count)
                progress(min(samplingLocal * 0.55, 0.55))
                if processed == photos.count
                    || processed % sampleProgressStride == 0
                {
                    let elapsed = Date().timeIntervalSince(pendingStartedAt)
                    let speed =
                        elapsed > 0 ? Double(pendingProcessed) / elapsed : 0
                    let remaining = max(pendingTotal - pendingProcessed, 0)
                    let eta = speed > 0 ? Double(remaining) / speed : 0
                    smartCheckLogger.info(
                        "Sampling photos processed=\(processed, privacy: .public)/\(photos.count, privacy: .public) pending=\(pendingProcessed, privacy: .public)/\(pendingTotal, privacy: .public) speed=\(Int(speed.rounded()), privacy: .public)/s eta=\(formatDuration(eta), privacy: .public)"
                    )
                }

                if nextIndex < pendingIndexes.count {
                    enqueueTask(index: nextIndex, into: &group)
                    nextIndex += 1
                }
            }
        }

        if dirtyCacheWrites > 0 || cachePruned {
            saveSampleCache(cacheEntries, reason: "finalize")
        }

        let samples = orderedSamples.compactMap { $0 }
        return SampleBuildResult(
            samples: samples,
            missingImageCount: missingImageCount,
            slowImageLoadCount: slowImageLoadCount,
            cacheHitCount: cacheHitCount,
            cachedWriteCount: cachedWriteCount
        )
    }

    private static func assetFingerprint(for asset: PHAsset) -> String {
        let creation = asset.creationDate?.timeIntervalSince1970 ?? -1
        let modification = asset.modificationDate?.timeIntervalSince1970 ?? -1
        return
            "\(asset.pixelWidth)x\(asset.pixelHeight)|c:\(Int(creation))|m:\(Int(modification))"
    }

    private static func sampleFromCache(_ record: CachedSampleRecord)
        -> AnalysisSample?
    {
        var feature: VNFeaturePrintObservation?
        if let featureArchive = record.featureArchive {
            guard
                let decoded = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: featureArchive
                )
            else {
                return nil
            }
            feature = decoded
        }

        return AnalysisSample(
            id: record.id,
            width: record.width,
            height: record.height,
            creationDate: record.creationDate,
            dHash: record.dHash,
            aHash: record.aHash,
            feature: feature
        )
    }

    private static func cacheRecord(
        from sample: AnalysisSample,
        fingerprint: String
    ) -> CachedSampleRecord? {
        let featureArchive: Data?
        if let feature = sample.feature {
            guard
                let archived = try? NSKeyedArchiver.archivedData(
                    withRootObject: feature,
                    requiringSecureCoding: true
                )
            else {
                smartCheckLogger.error(
                    "Failed to archive feature print for id=\(sample.id, privacy: .private(mask: .hash))"
                )
                return nil
            }
            featureArchive = archived
        } else {
            featureArchive = nil
        }

        return CachedSampleRecord(
            id: sample.id,
            fingerprint: fingerprint,
            width: sample.width,
            height: sample.height,
            creationDate: sample.creationDate,
            dHash: sample.dHash,
            aHash: sample.aHash,
            featureArchive: featureArchive
        )
    }

    private static func loadSampleCache() -> [String: CachedSampleRecord] {
        guard let url = sampleCacheURL else { return [:] }
        guard let data = try? Data(contentsOf: url) else { return [:] }

        let decoder = PropertyListDecoder()
        guard
            let snapshot = try? decoder.decode(
                SampleCacheSnapshot.self,
                from: data
            ),
            snapshot.version == sampleCacheVersion,
            snapshot.imageTargetWidth == Int(imageTargetSize.width),
            snapshot.imageTargetHeight == Int(imageTargetSize.height)
        else {
            smartCheckLogger.info("Sample cache invalidated due to schema mismatch")
            return [:]
        }

        return snapshot.entries
    }

    private static func saveSampleCache(
        _ entries: [String: CachedSampleRecord],
        reason: String
    ) {
        guard let url = sampleCacheURL else { return }
        let fileManager = FileManager.default
        let folderURL = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
            let snapshot = SampleCacheSnapshot(
                version: sampleCacheVersion,
                generatedAt: Date(),
                imageTargetWidth: Int(imageTargetSize.width),
                imageTargetHeight: Int(imageTargetSize.height),
                entries: entries
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            smartCheckLogger.info(
                "Sample cache saved entries=\(entries.count, privacy: .public) reason=\(reason, privacy: .public)"
            )
        } catch {
            smartCheckLogger.error(
                "Failed to persist sample cache error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static var sampleCacheURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
            .first?
            .appendingPathComponent("SmartCheck", isDirectory: true)
            .appendingPathComponent(sampleCacheFileName)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let rounded = max(Int(seconds.rounded()), 0)
        let minutes = rounded / 60
        let secs = rounded % 60
        if minutes == 0 {
            return "\(secs)s"
        }
        return "\(minutes)m \(secs)s"
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

    private static func fetchScreenshotIDs(
        progress: ((Double) -> Void)? = nil
    ) -> [String] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtype & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let result = PHAsset.fetchAssets(with: options)
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        let total = max(result.count, 1)
        var processed = 0
        result.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
            processed += 1
            if processed == result.count
                || processed % sampleProgressStride == 0
            {
                progress?(Double(processed) / Double(total))
            }
        }
        progress?(1)
        return ids
    }

    private static func loadImageForAnalysis(asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact

            imageManager.requestImage(
                for: asset,
                targetSize: imageTargetSize,
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
