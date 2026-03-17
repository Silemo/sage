# Testing Guidelines

## Core Principles

- **Test behavior, not implementation** -- tests should verify what code does, not how it does it internally. Refactoring should not break tests.
- **One assertion concept per test** -- each test should verify a single logical behavior. Multiple `assert` calls are fine if they validate the same concept.
- **AI-generated tests require careful review** -- verify that assertions are meaningful, not just that the test compiles. AI tools often generate tests that pass trivially or test the wrong thing.

## Test Naming

Use descriptive names that communicate the scenario and expected outcome:

- **Given/When/Then**: `GivenExpiredToken_WhenValidating_ThenReturnsUnauthorized`
- **Should format**: `should_return_empty_list_when_no_results_found`
- **Method_Scenario_Result**: `GetUser_WithInvalidId_ThrowsNotFoundException`

Choose the convention used by your project and be consistent.

## Test Structure

Follow the **Arrange / Act / Assert** pattern:

```
Arrange  -- set up test data and dependencies
Act      -- execute the behavior under test
Assert   -- verify the outcome
```

Keep each section short. If Arrange is long, extract a helper or use fixtures.

## Test Data

- Use minimal, focused test data -- only include fields relevant to the test
- Use builder patterns or factory functions for complex objects
- Avoid sharing mutable state between tests
- Use descriptive variable names: `expiredToken` not `token1`

## Mocking

- **Don't mock what you don't own** -- wrap external dependencies (HTTP clients, databases, file systems) behind interfaces, then mock the interface
- Prefer fakes and stubs over complex mock setups
- Verify interactions only when the interaction _is_ the behavior (e.g., "did we send an email?")
- Avoid mocking value objects and data structures

## Integration Tests

- Prefer integration tests for I/O-heavy code (database queries, HTTP calls, file operations)
- Use test containers or in-memory equivalents where possible
- Keep integration tests isolated -- each test should set up and tear down its own data

## Edge Cases

Always test:

- `null` / `None` / `undefined` inputs
- Empty collections and strings
- Boundary values (0, -1, MAX_INT, empty page, last page)
- Error conditions and exception paths
- Concurrent access where applicable

## Coverage

- Aim for high coverage on business logic and domain code
- Do not chase 100% coverage -- focus on value, not vanity metrics
- Skip trivial getters, setters, and pure boilerplate
- Treat uncovered critical paths as bugs
