// Logger.swift
// AgentSDK
//
// A lightweight, configurable logging system for the Agent SDK.

import Foundation
import os.log

// MARK: - Log Level

/// The severity level for log messages.
///
/// Log levels are ordered from most to least verbose:
/// - `debug`: Detailed information for debugging
/// - `info`: General informational messages
/// - `warning`: Potentially problematic situations
/// - `error`: Error conditions that should be addressed
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

// MARK: - Logger Configuration

/// Configuration options for the AgentSDK logger.
///
/// Use this to control logging behavior in your application:
///
/// ```swift
/// // Enable verbose logging during development
/// AgentLogger.configuration.minimumLevel = .debug
/// AgentLogger.configuration.isEnabled = true
///
/// // Disable logging in production
/// AgentLogger.configuration.isEnabled = false
/// ```
public struct LoggerConfiguration: Sendable {
    /// Whether logging is enabled. Defaults to `false`.
    public var isEnabled: Bool

    /// The minimum log level to output. Messages below this level are ignored.
    public var minimumLevel: LogLevel

    /// Whether to use Apple's unified logging system (os_log).
    /// When `false`, uses print statements instead.
    public var useOSLog: Bool

    /// Creates a new logger configuration.
    /// - Parameters:
    ///   - isEnabled: Whether logging is enabled. Defaults to `false`.
    ///   - minimumLevel: Minimum log level. Defaults to `.info`.
    ///   - useOSLog: Whether to use os_log. Defaults to `true`.
    public init(
        isEnabled: Bool = false,
        minimumLevel: LogLevel = .info,
        useOSLog: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.minimumLevel = minimumLevel
        self.useOSLog = useOSLog
    }
}

// MARK: - Agent Logger

/// A centralized logger for the AgentSDK framework.
///
/// The logger is disabled by default to avoid cluttering console output in production.
/// Enable it during development to debug agent behavior:
///
/// ```swift
/// // Enable debug logging
/// AgentLogger.configuration = LoggerConfiguration(
///     isEnabled: true,
///     minimumLevel: .debug
/// )
/// ```
///
/// ## Subsystems
///
/// The logger uses subsystems to categorize messages:
/// - `mcp`: Model Context Protocol client operations
/// - `runner`: Agent execution loop
/// - `provider`: LLM provider communications
/// - `tools`: Tool execution
///
/// ## Thread Safety
///
/// The logger is thread-safe and can be called from any context.
public enum AgentLogger {
    /// Global logger configuration.
    public static var configuration = LoggerConfiguration()

    private static let osLog = OSLog(subsystem: "com.agentsdk", category: "AgentSDK")

    /// Logs a debug message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - subsystem: Optional subsystem identifier (e.g., "mcp", "runner").
    public static func debug(_ message: @autoclosure () -> String, subsystem: String? = nil) {
        log(level: .debug, message: message(), subsystem: subsystem)
    }

    /// Logs an informational message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - subsystem: Optional subsystem identifier.
    public static func info(_ message: @autoclosure () -> String, subsystem: String? = nil) {
        log(level: .info, message: message(), subsystem: subsystem)
    }

    /// Logs a warning message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - subsystem: Optional subsystem identifier.
    public static func warning(_ message: @autoclosure () -> String, subsystem: String? = nil) {
        log(level: .warning, message: message(), subsystem: subsystem)
    }

    /// Logs an error message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - subsystem: Optional subsystem identifier.
    public static func error(_ message: @autoclosure () -> String, subsystem: String? = nil) {
        log(level: .error, message: message(), subsystem: subsystem)
    }

    private static func log(level: LogLevel, message: String, subsystem: String?) {
        guard configuration.isEnabled, level >= configuration.minimumLevel else { return }

        let prefix = subsystem.map { "[\($0)] " } ?? ""
        let fullMessage = "\(prefix)\(message)"

        if configuration.useOSLog {
            os_log("%{public}@", log: osLog, type: level.osLogType, fullMessage)
        } else {
            print("[\(level.prefix)] \(fullMessage)")
        }
    }
}
