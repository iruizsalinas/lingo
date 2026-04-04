# Contributing

Any kind of contribution is welcome. Bug reports, feature ideas, docs improvements, code, whatever. If you're unsure about something, just open an issue and we can figure it out together.

## Setup

```bash
git clone https://github.com/iruizsalinas/lingo.git
cd lingo
mix deps.get
mix test
```

## Running Tests

```bash
mix test                              # all tests
mix test test/lingo/cache_test.exs    # specific file
mix test test/lingo/cache_test.exs:42 # specific line
mix test --failed                     # re-run failures
```

## Code Style

Run `mix format` before committing. The project uses the default Elixir formatter config.

## Pull Requests

- Keep PRs focused on a single change when possible
- Tests for new features or bug fixes are appreciated
- Make sure `mix test` and `mix format --check-formatted` pass

Don't worry about getting everything perfect -- we can always iterate on a PR together.
