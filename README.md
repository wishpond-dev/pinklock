# Pinklock

Not-quite-a-redlock and uses `redix-sentinel` instead of `redix`.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pinklock` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pinklock, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/pinklock](https://hexdocs.pm/pinklock).

## Tests

Tests are built to run in docker-compose in order to have easy setup and teardown
of both redis and sentinel.

To run the tests:

```
docker-compose up
```

To format the code:

```
docker-compose run pinklock mix format
```
