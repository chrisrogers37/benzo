import Foundation

struct USBDevice: Identifiable {
    let id = UUID()
    let name: String
    let busPowerUsed: String?
}
