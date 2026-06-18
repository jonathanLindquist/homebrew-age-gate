# AGENTS.md

## Project

`homebrew-age-gate` is a PATH-level `brew` wrapper. Its critical guarantee is that `brew upgrade` must only upgrade Homebrew formulae/casks whose Homebrew package definition is old enough under the configured policy.

Default policy: package definitions must be at least 7 days old. Age means the last git committer timestamp for the Homebrew formula/cask definition file, not upstream release age.

## Core Safety Rules

- Never run real `brew update`, real `brew upgrade`, or any command path that can update or upgrade the developer machine's Homebrew formulae/casks while building or testing this project.
- Tests must use fake `brew` executables and temporary git tap repositories.
- Never call bare `brew upgrade` from the wrapper. Always compute an explicit allowlist first.
- Preserve the age-gate guarantee by failing closed when package age cannot be determined, except for explicitly named unsafe config opt-ins.
- Delegate non-upgrade commands to the configured real Homebrew executable unchanged.

## Implementation Notes

- Runtime is Ruby, using stdlib where possible.
- Project Ruby is pinned with `.ruby-version`.
- Bundler is configured through `.bundle/config` to install gems into `vendor/bundle` and avoid shared gems.
- The main shim is `bin/brew`.
- The diagnostic CLI is `bin/homebrew-age-gate`.
- Core code lives under `lib/homebrew_age_gate/`.
- Tests live under `test/` and use Minitest.

## Setup

Use rbenv with the project Ruby version:

```sh
ruby -v
```

Install project gems locally:

```sh
bundle install
```

Run tests through Bundler:

```sh
bundle exec rake test
```

If shell rbenv shims are not active, use:

```sh
rbenv exec bundle install
rbenv exec bundle exec rake test
```

## Testing Expectations

- Prefer `bundle exec rake test` for the full suite.
- New behavior needs tests, especially for fail-closed paths and Homebrew delegation safety.
- Integration tests must route Homebrew calls through the fake-brew harness.
- Any test that inspects upgrade behavior should assert that no real update/upgrade path was invoked.

## GitHub Hygiene

- Do not commit `vendor/bundle/`, IDE metadata, `.DS_Store`, or local personal config.
- Do commit `.bundle/config`, `.ruby-version`, `Gemfile`, and `Gemfile.lock`.
- Keep instructions concise and project-specific; avoid putting personal preferences here.

