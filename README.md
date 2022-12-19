# StepWise

`StepWise` is an Elixir library to wrap sequences of code which might fail.

 * It encourages standards by requiring the use of `{:ok, _}` and `{:error, _}` tuples (no `:ok`, or `{:error, _, _}`)
 * It rescues / catches anything which bubbles up so that you don't have to.  All exceptions/throws can be returned as `{:error, _}` tuples with` StepWise.resolve` or raised as an exception with `StepWise.resolve!`
 * It can perform operations on enumerables, requiring that each iteration succeeds (via `StepWise.map_step`)
 * It sends `telemetry` events which you can subscribe to do whatever you like across all processes using `StepWise` (i.e. logging, metrics, tracing, etc...)

# Code Sample



```elixir
defmodule MyApp.NotifyCommenters do
  def run(post) do
    post
    |> StepWise.step(&get_comments/1)
    |> StepWise.map_step(&get_commenter/1)
    |> StepWise.step(&notify_users/1)
    |> StepWise.resolve()
  end

  def get_comments(post) do
    # ...
  end

  def get_commenter(comment) do
    # ...
  end

  def notify_users(user) do
    # ...
  end
end
```




# TODO TODO TODO

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

