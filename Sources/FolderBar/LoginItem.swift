import ServiceManagement

/// SMAppService replaces the legacy SMLoginItemSetEnabled/helper-bundle
/// approach with a single in-process call (macOS 13+, matches our min target).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
    }
}
