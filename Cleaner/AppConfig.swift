import Foundation

enum AppLinks {
    static let termsOfUse = URL(string: "https://docs.google.com/document/d/e/2PACX-1vR5q6cfItgI2wMVaZo6zEQc-FV3nU8T03BN9DMJgMvd2-LSdWpo2sinS4K5f-h00m2uFz8O1vbWUIYy/pub")!
    static let privacyPolicy = URL(string: "https://docs.google.com/document/d/e/2PACX-1vR5q6cfItgI2wMVaZo6zEQc-FV3nU8T03BN9DMJgMvd2-LSdWpo2sinS4K5f-h00m2uFz8O1vbWUIYy/pub")!
    static let shareApp = URL(string: "https://apps.apple.com/app/id6760419354")!
    static let support = URL(string: "mailto:floriang@genaigmbh.com")!
    static let rateUs = URL(string: "https://apps.apple.com/app/id6760419354")!
}

enum AppSubscriptionIDs {
    static let weekly = "weeklyclean"
    static let monthly = "monthlyclean"
    static let yearly = "yearlyclean"

    static let all = [weekly, monthly, yearly]
}
