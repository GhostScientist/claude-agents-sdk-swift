import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

/// Macro that generates Tool conformance from a struct with an execute method
///
/// Usage:
/// ```swift
/// @Tool("Get the current weather for a location")
/// struct WeatherTool {
///     func execute(city: String, units: String = "celsius") async throws -> WeatherResult {
///         // Implementation
///     }
/// }
/// ```
public struct ToolMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }

        // Get the description from the macro argument
        let description = extractDescription(from: node) ?? "No description"

        // Find the execute method
        guard let executeMethod = findExecuteMethod(in: structDecl) else {
            throw MacroError.missingExecuteMethod
        }

        // Extract parameters from the execute method
        let parameters = extractParameters(from: executeMethod)

        // Generate the tool name (snake_case from struct name)
        let structName = structDecl.name.text
        let toolName = toSnakeCase(structName.replacingOccurrences(of: "Tool", with: ""))

        // Generate the Input struct
        let inputStruct = generateInputStruct(parameters: parameters)

        // Generate the static properties
        let nameDecl: DeclSyntax = """
            public static let name: String = "\(raw: toolName)"
            """

        let descriptionDecl: DeclSyntax = """
            public static let description: String = "\(raw: description)"
            """

        // Generate the inputSchema
        let schemaDecl = generateInputSchema(parameters: parameters)

        // Generate the execute(arguments:context:) method
        let executeDecl = generateExecuteMethod(parameters: parameters)

        return [
            inputStruct,
            nameDecl,
            descriptionDecl,
            schemaDecl,
            executeDecl,
        ]
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let toolExtension: DeclSyntax = """
            extension \(type.trimmed): Tool {}
            """

        guard let extensionDecl = toolExtension.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [extensionDecl]
    }

    // MARK: - Helpers

    private static func extractDescription(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }

    private static func findExecuteMethod(in structDecl: StructDeclSyntax) -> FunctionDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self),
               funcDecl.name.text == "execute" {
                return funcDecl
            }
        }
        return nil
    }

    private static func extractParameters(from method: FunctionDeclSyntax) -> [ToolParameter] {
        var parameters: [ToolParameter] = []

        for param in method.signature.parameterClause.parameters {
            // Skip context parameter if present
            let typeName = param.type.description.trimmingCharacters(in: .whitespaces)
            if typeName.contains("AgentContext") || typeName == "some AgentContext" {
                continue
            }

            let name = param.secondName?.text ?? param.firstName.text
            let hasDefault = param.defaultValue != nil
            let defaultValue = param.defaultValue?.value.description

            parameters.append(ToolParameter(
                name: name,
                type: typeName,
                hasDefault: hasDefault,
                defaultValue: defaultValue
            ))
        }

        return parameters
    }

    private static func generateInputStruct(parameters: [ToolParameter]) -> DeclSyntax {
        let properties = parameters.map { param -> String in
            if param.hasDefault {
                return "let \(param.name): \(param.type)?"
            } else {
                return "let \(param.name): \(param.type)"
            }
        }.joined(separator: "\n        ")

        return """
            private struct Input: Codable {
                \(raw: properties)
            }
            """
    }

    private static func generateInputSchema(parameters: [ToolParameter]) -> DeclSyntax {
        let propertiesCode = parameters.map { param -> String in
            let schemaType = swiftTypeToSchemaType(param.type)
            return """
            "\(param.name)": PropertySchema(type: .\(schemaType), description: "\(param.name) parameter")
            """
        }.joined(separator: ",\n                ")

        let requiredParams = parameters.filter { !$0.hasDefault }.map { "\"\($0.name)\"" }
        let requiredArray = requiredParams.isEmpty ? "nil" : "[\(requiredParams.joined(separator: ", "))]"

        return """
            public static let inputSchema: JSONSchema = JSONSchema(
                type: .object,
                description: nil,
                properties: [
                    \(raw: propertiesCode)
                ],
                required: \(raw: requiredArray)
            )
            """
    }

    private static func generateExecuteMethod(parameters: [ToolParameter]) -> DeclSyntax {
        let paramCalls = parameters.map { param -> String in
            if param.hasDefault {
                let defaultVal = param.defaultValue ?? "nil"
                return "\(param.name): input.\(param.name) ?? \(defaultVal)"
            } else {
                return "\(param.name): input.\(param.name)"
            }
        }.joined(separator: ", ")

        return """
            public func execute(arguments: String, context: any AgentContext) async throws -> String {
                let decoder = JSONDecoder()
                let input = try decoder.decode(Input.self, from: Data(arguments.utf8))
                let result = try await execute(\(raw: paramCalls))
                let encoder = JSONEncoder()
                let data = try encoder.encode(result)
                return String(data: data, encoding: .utf8) ?? "{}"
            }
            """
    }

    private static func swiftTypeToSchemaType(_ type: String) -> String {
        let cleanType = type.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
        switch cleanType {
        case "String": return "string"
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return "integer"
        case "Double", "Float", "Float16", "Float32", "Float64": return "number"
        case "Bool": return "boolean"
        case let t where t.hasPrefix("["): return "array"
        default: return "string"
        }
    }

    private static func toSnakeCase(_ input: String) -> String {
        var result = ""
        for (index, char) in input.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result += "_"
                }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }
}

// MARK: - Supporting Types

struct ToolParameter {
    let name: String
    let type: String
    let hasDefault: Bool
    let defaultValue: String?
}

enum MacroError: Error, CustomStringConvertible {
    case notAStruct
    case missingExecuteMethod
    case invalidParameter(String)

    var description: String {
        switch self {
        case .notAStruct:
            return "@Tool can only be applied to structs"
        case .missingExecuteMethod:
            return "@Tool requires an 'execute' method"
        case .invalidParameter(let name):
            return "Invalid parameter: \(name)"
        }
    }
}
