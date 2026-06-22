# homebrew-age-gate

`homebrew-age-gate` is a PATH-level `brew` wrapper that delays `brew upgrade` until each outdated Homebrew package definition has been present in the tap git history for a configured minimum age.

Default policy: upgrade only outdated formulae whose Homebrew definition last changed more than 7 days ago. A package definition exactly at the configured age threshold is still too new. Casks are only considered for explicit cask upgrade commands.

## Install Shape

Clone this repo and, from the checkout root, place its `bin` directory before Homebrew on `PATH`:

```sh
export PATH="$PWD/bin:$PATH"
```

The wrapper delegates non-upgrade commands to `/opt/homebrew/bin/brew` unchanged. Override that path with:

```sh
export HOMEBREW_AGE_GATE_REAL_BREW=/opt/homebrew/bin/brew
```

For one shell session from the repo root:

```sh
export PATH="$(pwd)/bin:$PATH"
```

Verify that the wrapper is first on `PATH`:

```sh
command -v brew
# should print this checkout's bin/brew
```

Verify that the wrapper still delegates to real Homebrew for non-upgrade commands:

```sh
brew --version
```

## Config

Create `$XDG_CONFIG_HOME/homebrew-age-gate/config.json` or `~/.config/homebrew-age-gate/config.json`:

```json
{
  "min_age_days": 7,
  "allow_auto_updates_casks": ["homebrew/cask/slack"],
  "unsafe_allow_unknown_age": [],
  "unsafe_preserve_installed_dependents_check": false
}
```

Package identities are canonical names such as `homebrew/core/jq` and `homebrew/cask/google-chrome`. Short names for `homebrew/core` formulae and `homebrew/cask` casks are accepted for convenience, but reports print canonical names.

Casks with `version: latest` are age-gated like any other package. No separate `latest` allowlist is needed.

If `XDG_CONFIG_HOME` points inside this checkout, the wrapper falls back to `$HOME/.config/homebrew-age-gate/config.json` for its own config. Set `HOMEBREW_AGE_GATE_CONFIG` for an explicit path.

Homebrew's own trust file stays Homebrew-owned. The wrapper does not create, copy, or read `trust.json`; when it invokes real Homebrew, it passes `HOMEBREW_USER_CONFIG_HOME` so Homebrew uses `$XDG_CONFIG_HOME/homebrew` for normal XDG setups and `$HOME/.homebrew` if `XDG_CONFIG_HOME` points inside this checkout. An explicitly set `HOMEBREW_USER_CONFIG_HOME` is preserved.

## Local Ruby Environment

This project is pinned to Ruby `4.0.2` with `.ruby-version`. With `rbenv` initialized in your shell, entering the repo should select that Ruby automatically:

```sh
cd "$HOME/projects/homebrew-age-gate"
ruby -v
```

Bundler is configured in `.bundle/config` to install project gems into `vendor/bundle` and avoid shared gems. To build the local environment from a clean checkout, run:

```sh
bundle install
```

If `which bundle` points at `/usr/bin/bundle` instead of an rbenv shim, your shell is not using rbenv for this repo yet. Either initialize rbenv in your shell or use the explicit form:

```sh
rbenv exec bundle install
```

After that, run project commands through Bundler:

```sh
bundle exec rake test
```

The expected setup files are:

```text
.ruby-version        # selects Ruby 4.0.2 with rbenv
Gemfile              # declares development/test gems
.bundle/config       # installs gems into vendor/bundle
vendor/bundle/       # local installed gems, ignored by git
```

## Commands

```sh
brew upgrade
brew upgrade jq
brew upgrade --cask visual-studio-code
homebrew-age-gate plan
homebrew-age-gate doctor
```

Bare `brew upgrade` only discovers and upgrades formulae. Cask upgrades are left alone unless you explicitly invoke a cask upgrade path; if you prefer `brew cu`, that command passes through unchanged. `brew outdated` passes through to real Homebrew, then annotates human-readable output with age-gate version and age details in a table:

```text
Formulae
name         current version  latest version  age  safe version  safe age
aws-sam-cli  1.161.0          1.162.1         4d   1.161.1       18d
btop         1.4.6            1.4.7           10d

Casks
name    current version  latest version  age  safe version  safe age
apidog  2.8.33           2.8.34          5d   2.8.33       12d
```

`brew update`, `brew info`, and every other non-upgrade command pass through to real Homebrew unchanged.

## Safe Testing

The safe test suite uses a fake `brew` executable and temporary git tap repositories. It does not run real `brew update`, real `brew upgrade`, or any real package upgrade.

Build the local Ruby environment:

```sh
bundle install
```

Run all tests:

```sh
bundle exec rake test
```

If your shell is not using rbenv shims yet, run the same commands explicitly through rbenv:

```sh
rbenv exec bundle install
rbenv exec bundle exec rake test
```

Expected result:

```text
55 runs, 372 assertions, 0 failures, 0 errors, 0 skips
```

Run targeted test files while developing:

```sh
bundle exec ruby -Ilib:test test/wrapper_integration_test.rb
bundle exec ruby -Ilib:test test/planner_test.rb
bundle exec ruby -Ilib:test test/config_test.rb
```

## Actual Usage

Use this only when you are ready for the wrapper to inspect real Homebrew state. `homebrew-age-gate plan` and wrapper-driven `brew upgrade --dry-run` do not install package upgrades, but they do call real Homebrew discovery commands. `brew upgrade` performs real upgrades after filtering.

1. Build the local Ruby environment:

   ```sh
   cd "$HOME/projects/homebrew-age-gate"
   bundle install
   ```

2. Put the wrapper before Homebrew on `PATH`:

   ```sh
   export PATH="$(pwd)/bin:$PATH"
   command -v brew
   ```

3. Check wrapper setup without running Homebrew:

   ```sh
   homebrew-age-gate doctor
   ```

4. Preview the age-gated plan:

   ```sh
   homebrew-age-gate plan
   ```

5. Ask the wrapper to validate the final Homebrew dry-run plan:

   ```sh
   brew upgrade --dry-run
   ```

6. Run the real filtered upgrade only when the plan looks correct:

   ```sh
   brew upgrade
   ```

You can target explicit packages, but explicit names are still age-gated:

```sh
brew upgrade jq
brew upgrade --cask visual-studio-code
```

## Development Safety

Do not run real `brew update` or real `brew upgrade` while building or testing this project. The test suite uses a fake `brew` executable and temporary git tap repositories.
