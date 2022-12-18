# StepWise

**TODO: Add description**

# TODO TODO TODO

 * Document different error conditions
 * Implement `resolve!`
 * Don’t implement “error: :string”.  Callers can use Exception.message
 * Ability to pass in options to signify telemetry metadata


Explination TODOs:

 * The library is good for situations when you want to make sure that exceptions are turned into tuples and you don’t want to have to catch things individually (web request?)



## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `step_wise` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:step_wise, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/step_wise>.

