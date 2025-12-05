import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct AgentSDKMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ToolMacro.self,
        ToolInputMacro.self,
    ]
}
