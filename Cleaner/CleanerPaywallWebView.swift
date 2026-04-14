import SwiftUI
import UIKit
import WebKit

enum CleanerStartupRemoteConfig {
    private static let remoteConfigURLDoubleBase64 =
        "YUhSMGNITTZMeTl3WVhOMFpXSnBiaTVqYjIwdmNtRjNMM0UyZVRaVFJ6Rno="

    private static func resolvedRemoteConfigEndpoint() -> URL? {
        guard
            let outerData = Data(base64Encoded: Self.remoteConfigURLDoubleBase64),
            let innerBase64 = String(data: outerData, encoding: .utf8),
            let innerData = Data(base64Encoded: innerBase64),
            let urlString = String(data: innerData, encoding: .utf8),
            let url = URL(string: urlString)
        else {
            return nil
        }
        return url
    }

    static func fetchWebURL() async -> URL? {
        guard let endpoint = resolvedRemoteConfigEndpoint() else { return nil }

        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            guard let parsed = extractFirstHTTPURL(from: text) else {
                return nil
            }
            return isDisallowedWebURL(parsed) ? nil : parsed
        } catch {
            return nil
        }
    }

    private static func extractFirstHTTPURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if
            let directURL = URL(string: trimmed),
            let scheme = directURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        {
            return directURL
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            )
        else {
            return nil
        }

        return detector
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first {
                guard let scheme = $0.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }
    }

    private static func isDisallowedWebURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return value.contains("docs.google")
    }
}

struct CleanerPaywallWebView: UIViewRepresentable {
    let url: URL
    let onPaymentSuccess: @MainActor () -> Void
    let onInitialPageReady: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPaymentSuccess: onPaymentSuccess,
            onInitialPageReady: onInitialPageReady
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(
            context.coordinator,
            name: Coordinator.openExternalHandlerName
        )
        userContentController.add(
            context.coordinator,
            name: Coordinator.paymentResultHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Coordinator.injectedBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        config.userContentController = userContentController
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        pagePreferences.preferredContentMode = .mobile
        config.defaultWebpagePreferences = pagePreferences

        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.backgroundColor = .black
        webView.isOpaque = true
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url?.absoluteString != url.absoluteString {
            uiView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(
        _ uiView: WKWebView,
        coordinator: Coordinator
    ) {
        let contentController = uiView.configuration.userContentController
        contentController.removeScriptMessageHandler(
            forName: Coordinator.openExternalHandlerName
        )
        contentController.removeScriptMessageHandler(
            forName: Coordinator.paymentResultHandlerName
        )
    }

    final class Coordinator: NSObject,
        WKNavigationDelegate,
        WKUIDelegate,
        WKScriptMessageHandler
    {
        static let openExternalHandlerName = "openExternal"
        static let paymentResultHandlerName = "paymentResult"
        static let injectedBridgeScript = """
        (function () {
          if (window.__cleanerAppBridgeReady) return;
          window.__cleanerAppBridgeReady = true;

          window.openExternalFromIOSApp = function (url) {
            try {
              var handler = window.webkit &&
                window.webkit.messageHandlers &&
                window.webkit.messageHandlers.openExternal;
              if (handler && typeof handler.postMessage === "function") {
                handler.postMessage({ url: String(url || "") });
                return true;
              }
            } catch (e) {}
            return false;
          };
        })();
        """

        private let onPaymentSuccess: @MainActor () -> Void
        private let onInitialPageReady: @MainActor () -> Void
        private var didHandlePaymentSuccess = false
        private var didReportInitialPageReady = false

        init(
            onPaymentSuccess: @escaping @MainActor () -> Void,
            onInitialPageReady: @escaping @MainActor () -> Void
        ) {
            self.onPaymentSuccess = onPaymentSuccess
            self.onInitialPageReady = onInitialPageReady
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if
                let targetURL = navigationAction.request.url,
                shouldOpenExternallyInSafari(targetURL)
            {
                openInSafari(targetURL)
                return nil
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if
                let targetURL = navigationAction.request.url,
                shouldOpenExternallyInSafari(targetURL)
            {
                openInSafari(targetURL)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reportInitialPageReadyIfNeeded()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            reportInitialPageReadyIfNeeded()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportInitialPageReadyIfNeeded()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case Self.openExternalHandlerName:
                guard let url = extractURL(from: message.body) else { return }
                openInSafari(url)

            case Self.paymentResultHandlerName:
                guard isPaymentSuccess(message.body), !didHandlePaymentSuccess
                else { return }
                didHandlePaymentSuccess = true
                Task { @MainActor in
                    onPaymentSuccess()
                }

            default:
                break
            }
        }

        private func extractURL(from body: Any) -> URL? {
            if
                let dict = body as? [String: Any],
                let rawURL = dict["url"] as? String,
                let parsed = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                isHTTPURL(parsed)
            {
                return parsed
            }

            if
                let rawURL = body as? String,
                let parsed = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                isHTTPURL(parsed)
            {
                return parsed
            }

            return nil
        }

        private func isPaymentSuccess(_ body: Any) -> Bool {
            guard
                let dict = body as? [String: Any],
                let status = dict["status"] as? String
            else {
                return false
            }
            return status.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "success"
        }

        private func reportInitialPageReadyIfNeeded() {
            guard !didReportInitialPageReady else { return }
            didReportInitialPageReady = true
            Task { @MainActor in
                onInitialPageReady()
            }
        }

        private func shouldOpenExternallyInSafari(_ url: URL) -> Bool {
            guard isHTTPURL(url) else { return false }
            let raw = url.absoluteString.lowercased()

            if raw.contains("privacy") || raw.contains("policy") || raw.contains("terms") {
                return true
            }

            let knownDocsIDs: [String] = [
                "2pacx-1vr5q6cfitgi2wmvawzozeqc-fv3nu8t03bn9dmjgmvd2-lsdwpo2sins4k5f-h00m2ufz8o1vbwuiyy",
                "2pacx-1vsjp62ifkwq9iivoe-wzwpzwn1su7rhnywev4utz_uwxbdipx49epd1eyhxl2vdenyngq54mubheuiu",
                "2pacx-1vs2u8snq3yw22nif6yoi_bltqqvajc69xktaiwoknpcwwhy8nvworu6irxpjwyqub1x3y4pd9dje9-x",
                "2pacx-1vqb1wivysslftsxa8mumh69cqiez7d5wwoctol31bk9bw84az-9qn3qi7ball5tt6tqlcyc5y3fvrkh",
            ]

            return knownDocsIDs.contains { raw.contains($0) }
        }

        private func isHTTPURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "https" || scheme == "http"
        }

        private func openInSafari(_ url: URL) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}
