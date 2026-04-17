import Foundation
import OSLog

public enum AppLog {
    private static let subsystem = "com.bizarrecrm"

    public static let app         = Logger(subsystem: subsystem, category: "app")
    public static let auth        = Logger(subsystem: subsystem, category: "auth")
    public static let networking  = Logger(subsystem: subsystem, category: "networking")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let sync        = Logger(subsystem: subsystem, category: "sync")
    public static let ws          = Logger(subsystem: subsystem, category: "websocket")
    public static let pos         = Logger(subsystem: subsystem, category: "pos")
    public static let hardware    = Logger(subsystem: subsystem, category: "hardware")
    public static let ui          = Logger(subsystem: subsystem, category: "ui")
}
