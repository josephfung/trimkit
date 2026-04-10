# Contributing to TrimKit

Suggestions, bug reports, and pull requests are welcome. TrimKit is intentionally small — contributions that add focused hooks, agents, or skills fit best.

## AI contributions

PRs authored or co-authored with AI tools are explicitly welcome. TrimKit exists to make AI-assisted workflows better, so it would be strange to exclude them.

## How to contribute

1. Open an issue first for anything non-trivial — a quick alignment check saves everyone time
2. Fork the repo and work on a feature branch
3. Add or update tests in `tests/` for any hook or script changes
4. Run the test suite before opening a PR:
   ```bash
   git submodule update --init --recursive
   ./tests/test_helper/bats-core/bin/bats tests/
   ```
5. Add a bullet to the `[Unreleased]` section of `CHANGELOG.md` for notable changes

## What fits

- New hooks that enforce useful guardrails in Claude Code
- New agents or skills that add reusable capabilities
- Improvements to the installer or test coverage
- Bug fixes and documentation corrections

## What probably doesn't fit

- Large framework changes or abstractions
- Features that only apply to a very specific personal setup

If you're unsure, open an issue and ask.
