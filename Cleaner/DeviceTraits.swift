import UIKit

enum DeviceTraits {
    static var isSmallDevice: Bool {
        let screenHeight = max(
            UIScreen.main.bounds.width,
            UIScreen.main.bounds.height
        )
        return screenHeight <= 667
    }
}
