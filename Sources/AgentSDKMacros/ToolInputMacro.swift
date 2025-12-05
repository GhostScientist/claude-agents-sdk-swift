import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

/// Macro that generates JSON Schema for tool input/output types
///
/// Usage:
/// ```swift
/// @ToolInput
/// struct WeatherResult: Codable {
///     let temperature: Double
///     let conditions: String
/// }
/// ```
public struct ToolInputMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Handle structs
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return try expandStruct(structDecl)
        }

        // Handle enums
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            return try expandEnum(enumDecl)
        }

        throw ToolInputMacroError.unsupportedType
    }

    private static func expandStruct(_ structDecl: StructDeclSyntax) throws -> [DeclSyntax] {
        var properties: [(name: String, type: String)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                       let typeAnnotation = binding.typeAnnotation {
                        let name = identifier.identifier.text
                        let type = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                        properties.append((name: name, type: type))
                    }
                }
            }
        }

        let propertiesCode = properties.map { prop -> String in
            let schemaType = swiftTypeToSchemaType(prop.type)
            return """
                "\(prop.name)": PropertySchema(type: .\(schemaType), description: nil)
            """
        }.joined(separator: ",\n            ")

        let requiredProps = properties.filter { !$0.type.hasSuffix("?") }.map { "\"\($0.name)\"" }
        let requiredArray = requiredProps.isEmpty ? "nil" : "[\(requiredProps.joined(separator: ", "))]"

        let schemaDecl: DeclSyntax = """
            public static var jsonSchema: JSONSchema {
                JSONSchema(
                    type: .object,
                    description: nil,
                    properties: [
                        \(raw: propertiesCode)
                    ],
                    required: \(raw: requiredArray)
                )
            }
            """

        return [schemaDecl]
    }

    private static func expandEnum(_ enumDecl: EnumDeclSyntax) throws -> [DeclSyntax] {
        var cases: [String] = []

        for member in enumDecl.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDecl.elements {
                    cases.append(element.name.text)
                }
            }
        }

        let enumValues = cases.map { "\"\($0)\"" }.joined(separator: ", ")

        let schemaDecl: DeclSyntax = """
            public static var jsonSchema: JSONSchema {
                JSONSchema(
                    type: .string,
                    description: nil,
                    properties: nil,
                    required: nil,
                    items: nil,
                    enumValues: [\(raw: enumValues)]
                )
            }
            """

        return [schemaDecl]
    }

    private static func swiftTypeToSchemaType(_ type: String) -> String {
        let cleanType = type.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
        switch cleanType {
        case "String": return "string"
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return "integer"
        case "Double", "Float", "Float16", "Float32", "Float64": return "number"
        case "Bool": return "boolean"
        case let t where t.hasPrefix("["): return "array"
        default: return "object"
        }
    }
}

enum ToolInputMacroError: Error, CustomStringConvertible {
    case unsupportedType

    var description: String {
        switch self {
        case .unsupportedType:
            return "@ToolInput can only be applied to structs or enums"
        }
    }
}
