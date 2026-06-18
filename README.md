# homebrew-age-gate

`homebrew-age-gate` is a PATH-level `brew` wrapper that delays `brew upgrade` until each outdated Homebrew package definition has been present in the tap git history for a configured minimum age.

Default policy: upgrade only outdated formulae/casks whose Homebrew definition last changed at least 7 days ago.

## Install Shape

Clone this repo and place its `bin` directory before Homebrew on `PATH`:

```sh
export PATH="/path/to/homebrew-age-gate/bin:$PATH"
```

The wrapper delegates non-upgrade commands to `/opt/homebrew/bin/brew` unchanged. Override that path with:

```sh
export HOMEBREW_AGE_GATE_REAL_BREW=/opt/homebrew/bin/brew
```

## Config

Create `$XDG_CONFIG_HOME/homebrew-age-gate/config.json` or `~/.config/homebrew-age-gate/config.json`:

```json
{
  "min_age_days": 7,
  "allow_auto_updates_casks": ["homebrew/cask/slack"],
  "allow_latest_casks": [],
  "unsafe_allow_unknown_age": [],
  "unsafe_preserve_installed_dependents_check": false
}
```

Package identities are canonical names such as `homebrew/core/jq` and `homebrew/cask/google-chrome`. Short names for `homebrew/core` formulae and `homebrew/cask` casks are accepted for convenience, but reports print canonical names.

## Local Ruby Environment

This project is pinned to Ruby `4.0.2` with `.ruby-version`. With `rbenv` initialized in your shell, entering the repo should select that Ruby automatically:

```sh
cd /path/to/homebrew-age-gate
ruby -v
```

Bundler is configured in `.bundle/config` to install project gems into `vendor/bundle` and avoid shared gems. To build the local environment from a clean checkout, run:

```sh
bundle install
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
homebrew-age-gate plan
homebrew-age-gate doctor
```

`brew update`, `brew outdated`, `brew info`, and every other non-upgrade command pass through to real Homebrew.

## Development Safety

Do not run real `brew update` or real `brew upgrade` while building or testing this project. The test suite uses a fake `brew` executable and temporary git tap repositories.
