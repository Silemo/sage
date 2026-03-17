# Java Conventions

## Target Platform

- Java 21+
- Use modern language features: records, sealed classes, pattern matching for `switch`, record patterns, text blocks, sequenced collections, virtual threads

## Type Design

- Use `record` types for immutable data carriers
- Use sealed classes and interfaces to restrict type hierarchies where appropriate
- Use record patterns to destructure records in `instanceof` and `switch`: `case Point(int x, int y) ->`
- Prefer composition over inheritance
- Use `Optional<T>` for return types that may be absent; never use `Optional` as a field or parameter

## Style

- Follow the [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)
- Prefer `var` for local variables when the type is obvious from context
- Prefer streams over imperative loops for collection transformations
- Use text blocks (`"""`) for multi-line strings
- Use pattern matching for `switch` instead of `if`/`else instanceof` chains
- Use guarded patterns (`case Foo f when f.isValid() ->`) instead of nested `if` inside case blocks
- Use `SequencedCollection`, `SequencedSet`, and `SequencedMap` interfaces when insertion-order access (`.getFirst()`, `.getLast()`, `.reversed()`) is needed

## Concurrency

- Prefer virtual threads (`Thread.ofVirtual()`, `Executors.newVirtualThreadPerTaskExecutor()`) for I/O-bound workloads
- Reserve platform threads for CPU-bound or pinning-sensitive tasks
- Avoid `synchronized` blocks in virtual-thread code paths; use `ReentrantLock` to prevent carrier-thread pinning
- Use structured concurrency patterns where supported by your framework

## Dependency Injection

- Prefer constructor injection over field injection
- Use `final` fields for injected dependencies
- Avoid service locator patterns

## Logging

- Use SLF4J as the logging facade with Logback as the implementation
- Use parameterized messages: `log.info("User {} created", userId)`
- Never log sensitive data

## Error Handling

- Use specific exception types -- avoid catching `Exception` or `Throwable` broadly
- Prefer unchecked exceptions for programming errors
- Document checked exceptions in Javadoc `@throws`

## Testing

- **Framework**: JUnit 5 + Mockito
- Use `@DisplayName` for descriptive test names
- Use `@Nested` classes to group related tests
- Use `@ParameterizedTest` with `@ValueSource` or `@CsvSource` for data-driven tests
- Prefer AssertJ for fluent assertions
- Name test methods: `shouldDoSomething_whenCondition`
