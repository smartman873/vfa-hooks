# Contributing

## Setup

```bash
./scripts/bootstrap.sh
```

## Development Flow

1. Create a feature branch.
2. Keep changes scoped and tested.
3. Run local checks before opening PR.

## Required Checks

```bash
cd contracts && forge build && forge test && forge coverage
cd ../frontend && pnpm install && pnpm build
./scripts/verify_commits.sh
```

## Commit Guidelines

- Use conventional commit prefixes (`feat:`, `fix:`, `test:`, `docs:`, `chore:`)
- Keep commit messages specific to changed subsystem
- Avoid mixing unrelated changes in one commit

## Documentation

Update docs when behavior, APIs, or deployment requirements change.
