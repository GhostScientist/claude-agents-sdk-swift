# Contributing to AgentSDK for Swift

Thank you for your interest in contributing to AgentSDK! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- **Xcode 15.0+** with Swift 5.9+
- **macOS 14.0+** for development
- An Anthropic API key for testing (optional, but recommended)

### Setting Up the Development Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/GhostScientist/claude-agents-sdk-swift.git
   cd claude-agents-sdk-swift
   ```

2. Open the package in Xcode:
   ```bash
   open Package.swift
   ```

3. Build to verify everything compiles:
   ```bash
   swift build
   ```

## Project Structure

```
agent-sdk-swift/
├── Sources/
│   ├── AgentSDK/           # Core framework
│   │   ├── Agent/          # Agent and Handoff types
│   │   ├── Runner/         # Execution engine
│   │   ├── Tools/          # Tool protocol and FunctionTool
│   │   ├── Guardrails/     # Input/output validation
│   │   ├── LLM/            # Provider protocol and types
│   │   ├── MCP/            # Model Context Protocol support
│   │   ├── Context/        # AgentContext types
│   │   ├── Messages/       # Message types
│   │   ├── Errors/         # Error types
│   │   └── Logging/        # Logging infrastructure
│   ├── ClaudeProvider/     # Anthropic Claude integration
│   ├── AgentSDKApple/      # SwiftUI and App Intents
│   └── AgentSDKMacros/     # Swift macros (future)
├── Tests/                  # Test suites
├── Examples/               # Example applications
└── Package.swift
```

## How to Contribute

### Reporting Issues

Before creating an issue, please:
1. Search existing issues to avoid duplicates
2. Use a clear, descriptive title
3. Include:
   - Swift and Xcode versions
   - macOS/iOS version
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant code snippets or error messages

### Submitting Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Write clear commit messages** describing what changed and why
3. **Add tests** for new functionality
4. **Update documentation** for API changes
5. **Ensure the build passes** (`swift build`)
6. **Run tests** (`swift test`)

### Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Follow existing code style and conventions
- Add DocC documentation for public APIs
- Include examples in documentation where helpful
- Update the README if adding major features

## Code Style

### Swift Conventions

- Use Swift's standard naming conventions
- Prefer `let` over `var` when possible
- Use meaningful variable and function names
- Keep functions focused and small

### Documentation

All public APIs should have DocC documentation including:
- A brief description
- Usage examples where appropriate
- Parameter descriptions
- Return value descriptions
- Thrown error descriptions

Example:
```swift
/// Runs an agent to completion and returns the final result.
///
/// This method executes the agent loop, handling all tool calls and handoffs
/// automatically, until the agent produces a final text response.
///
/// - Parameters:
///   - agent: The agent to execute.
///   - input: The user's input message.
///   - context: Optional context for state management.
/// - Returns: A ``RunResult`` containing the output and execution metadata.
/// - Throws: ``AgentError`` if execution fails.
///
/// ## Example
///
/// ```swift
/// let result = try await runner.run(agent, input: "Hello!")
/// print(result.output)
/// ```
public func run<A: AgentProtocol>(_ agent: A, input: String, context: A.Context = A.Context()) async throws -> RunResult
```

### Logging

Use the `AgentLogger` for debug output instead of `print()`:
```swift
AgentLogger.debug("Processing request", subsystem: "runner")
AgentLogger.warning("Rate limit approaching", subsystem: "provider")
```

## Testing

### Running Tests

```bash
swift test
```

### Writing Tests

- Place tests in the `Tests/` directory
- Test both success and failure cases
- Use descriptive test names
- Mock external dependencies

## Areas for Contribution

We especially welcome contributions in these areas:

### High Priority
- Unit tests for core functionality
- Integration tests with Claude API
- Additional LLM providers (OpenAI, Ollama, etc.)
- Performance optimizations

### Medium Priority
- Additional built-in guardrails
- More MCP server integrations
- Improved error messages
- Documentation improvements

### Nice to Have
- Example applications
- Tutorials and guides
- SwiftUI components
- Accessibility improvements

## Questions?

If you have questions about contributing, feel free to:
- Open a discussion on GitHub
- Create an issue with the "question" label

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make AgentSDK better!
