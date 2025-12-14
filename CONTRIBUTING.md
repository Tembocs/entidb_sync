# Contributing to EntiDB Sync

Thank you for your interest in contributing to EntiDB Sync!

## Development Setup

### Prerequisites
- Dart SDK ^3.10.1 (required by EntiDB)
  - Check your version: `dart --version`
  - Upgrade if needed: `dart channel stable && dart upgrade`
- Git
- Code editor (VS Code recommended)

### Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/Tembocs/entidb_sync.git
   cd entidb_sync
   ```

2. **Install dependencies for all packages**
   ```bash
   # Protocol package
   cd packages/entidb_sync_protocol
   dart pub get
   
   # Client package
   cd ../entidb_sync_client
   dart pub get
   
   # Server package
   cd ../entidb_sync_server
   dart pub get
   ```

3. **Run tests**
   ```bash
   # From repository root
   dart test packages/entidb_sync_protocol/test
   dart test packages/entidb_sync_client/test
   dart test packages/entidb_sync_server/test
   ```

## Project Structure

This is a monorepo with three packages:

- `packages/entidb_sync_protocol/` - Shared protocol definitions
- `packages/entidb_sync_client/` - Client sync engine
- `packages/entidb_sync_server/` - Reference server implementation

See [doc/repository_organization.md](doc/repository_organization.md) for detailed structure.

## Development Workflow

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following our coding standards:
   - Follow Dart style guide
   - Add tests for new functionality
   - Update documentation as needed
   - Ensure all tests pass

3. Run code analysis:
   ```bash
   dart analyze
   ```

4. Format code:
   ```bash
   dart format .
   ```

5. Commit with clear messages:
   ```bash
   git commit -m "feat: add feature description"
   ```

### Commit Message Convention

We use conventional commits:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Test additions/changes
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks

### Pull Request Process

1. Ensure all tests pass
2. Update documentation if needed
3. Add entry to CHANGELOG.md
4. Submit PR with clear description
5. Address review feedback

## Testing Guidelines

### Writing Tests

- Place tests in `test/` directory
- Use descriptive test names
- Cover edge cases
- Test error conditions

### Running Tests

```bash
# All tests
dart test

# Specific package
dart test packages/entidb_sync_protocol/test

# With coverage
dart test --coverage=coverage
dart pub global activate coverage
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

## Code Style

- Follow official [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Use `dart format` before committing
- Maximum line length: 80 characters
- Use trailing commas for better diffs

## Documentation

- Add dartdoc comments for public APIs
- Include usage examples
- Update README.md for major changes
- Keep architecture docs in sync

## Questions?

- Check existing issues on GitHub
- Review architecture documentation
- Ask in discussions

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
