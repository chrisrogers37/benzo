protocol LoginItemClient {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}
