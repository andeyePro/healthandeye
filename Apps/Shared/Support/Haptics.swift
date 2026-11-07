import Foundation
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

enum HapticKind: Sendable {
    case up, down, success, notify
}

@MainActor
enum Haptics {
    static func play(_ kind: HapticKind) {
        #if os(watchOS)
        let type: WKHapticType
        switch kind {
        case .up: type = .directionUp
        case .down: type = .directionDown
        case .success: type = .success
        case .notify: type = .notification
        }
        WKInterfaceDevice.current().play(type)
        #elseif os(iOS)
        switch kind {
        case .up, .down:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .notify:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}
