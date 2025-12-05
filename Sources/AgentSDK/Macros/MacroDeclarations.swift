import Foundation

/// Generates Tool protocol conformance from a struct with an execute method.
///
/// The macro will:
/// - Generate `name` and `description` static properties
/// - Generate `inputSchema` based on execute method parameters
/// - Generate `execute(arguments:context:)` that parses JSON and calls your method
///
/// ## Example
///
/// ```swift
/// @Tool("Get the current weather for a location")
/// struct WeatherTool {
///     func execute(city: String, units: String = "celsius") async throws -> WeatherResult {
///         // Your implementation
///     }
/// }
///
/// @ToolInput
/// struct WeatherResult: Codable {
///     let temperature: Double
///     let conditions: String
/// }
/// ```
///
/// Expands to a full Tool conformance with JSON schema generation.
@attached(member, names: named(Input), named(name), named(description), named(inputSchema), named(execute))
@attached(extension, conformances: Tool)
public macro Tool(_ description: String) = #externalMacro(
    module: "AgentSDKMacros",
    type: "ToolMacro"
)

/// Generates JSON Schema for tool input/output types.
///
/// Apply to structs or enums that are used as tool parameters or return values.
///
/// ## Example
///
/// ```swift
/// @ToolInput
/// enum TemperatureUnit: String, Codable {
///     case celsius
///     case fahrenheit
/// }
///
/// @ToolInput
/// struct WeatherResult: Codable {
///     let temperature: Double
///     let conditions: String
///     let humidity: Int
/// }
/// ```
@attached(member, names: named(jsonSchema))
public macro ToolInput() = #externalMacro(
    module: "AgentSDKMacros",
    type: "ToolInputMacro"
)
