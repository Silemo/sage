# C# Conventions

## Target Platform

- .NET 8+ / C# 12+
- Enable nullable reference types (`<Nullable>enable</Nullable>`)
- Enable implicit usings where appropriate

## Type Design

- Prefer `record` types for DTOs and immutable data carriers
- Use the `required` keyword for mandatory properties on classes and structs
- Prefer primary constructors where they simplify initialization
- Use sealed classes/interfaces where inheritance is not intended

## Naming

Follow Microsoft naming conventions:

| Element | Convention | Example |
|---|---|---|
| Public methods, properties | PascalCase | `GetUserAsync()` |
| Local variables, parameters | camelCase | `userName` |
| Private fields | `_camelCase` | `_logger` |
| Constants | PascalCase | `MaxRetryCount` |
| Interfaces | `I` prefix | `IUserRepository` |
| Async methods | `Async` suffix | `SaveAsync()` |

## Async and Cancellation

- Use `async`/`await` throughout -- avoid `.Result` or `.Wait()`
- Accept and forward `CancellationToken` on all async methods
- Prefer `ValueTask<T>` over `Task<T>` when results are often synchronous

## Logging

- Use `ILogger<T>` via dependency injection
- Use structured logging with message templates: `_logger.LogInformation("User {UserId} created", userId)`
- Never log sensitive data

## Patterns

- Prefer pattern matching (`is`, `switch` expressions) over type checks and casts
- Use collection expressions (`[1, 2, 3]`) where supported
- Prefer LINQ for declarative collection operations
- Use `ArgumentNullException.ThrowIfNull()` for guard clauses

## Testing

- **Framework**: xUnit
- Use `[Fact]` for single-case tests, `[Theory]` with `[InlineData]` for parameterized tests
- Prefer `FluentAssertions` or `Shouldly` for readable assertions
- Use `NSubstitute` or `Moq` for mocking
- Name tests: `MethodName_Scenario_ExpectedResult`
