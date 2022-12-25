# StepWise

`StepWise` is a light wrapper for the parts of your code which need to be debuggable in production.

That means that it:

 * ...encourages the breaking down of such code into step
 * ...requires that each step returns a success of failure state (via standard `{:ok, _}` and `{:error, _}` tuples)
 * ...provides telemetry events to separate/centralize code for concerns such as logging, metrics, and tracing.

Let's start with some code...

```elixir
defmodule MyApp.NotifyCommenters do
  # This outer `step` isn't neccessary, but it is a useful convention to be able to
  # track the status of the whole run in addition to individual steps.
  def run(post) do
    StepWise.step({:ok, post}, &run_steps/1)
  end

  def run_steps(post) do
    {:ok, post}
    |> StepWise.step(&MyApp.Posts.get_comments/1)
    |> StepWise.map_step(fn comment ->
      # get_commenter/1 doesn't return `{:ok, _}`, so we need
      # to do that here

      {:ok, MyApp.Posts.get_commenter(comment)}
    end)
    |> StepWise.step(&notify_users/1)
  end

  def notify_users(user) do
    # ...
  end
end
```

You might notice that the `step/1` and `map_step/1` functions take function values.  These can be anonymous (like used above in `map_step`), though errors will be clearer when using function values coming from named functions.

The `step` and `map_step` functions `rescue` / `catch` anything which bubbles up so that you don't have to.  All exceptions/throws can be returned as `{:error, _}` tuples so that they can be handled.  `exit`s, however, are *not* caught on purpose because, as [this Elixir guide](https://elixir-lang.org/getting-started/try-catch-and-rescue.html#exits) says: "exit signals are an important part of the fault tolerant system provided by the Erlang VM..."

`{:error, _}` tuples will always be returned with Exception values (i.e. all `{:error, _}` tuples returned which don't have exceptions will be wrapped).  This means that you can:

 * ...call `Exception.message` to get a string
 * ...`raise` the exception value if you want to raise the error
 * ...hand the exception to error-collecting services like Sentry, Rollbar, etc...
 * ...pattern match or act upon on the structure and attributes of the exception

If you are familiar with Elixir's `with`, you may be wondering about it's relation to `StepWise` since `with` also helps you handle a series of statements which could succeed or fail.  See below for more discussion `StepWise` vs `with`.

# Telemetry

As [my colleague](https://github.com/linduxed) put it: *"Logging definitely feels like one of those areas where it very quickly jumps from 'these sprinkled out log calls are giving us a lot of value' to 'we now have a mess in both code and log output'"*

Central to `StepWise` is it's telemetry events to allow actions such as logging, metrics, and tracing be separated as a different concern to your code.  There are three telemetry events:

## `[:step_wise, :step, :start]`

Executed when a step starts with the following metadata:

 * `id`: A unique ID generated by `:erlang.unique_integer()`
 * `step_func`: The function object given to the `step` / `step_map` function
 * `module`: The module where the `step_func` is defined (for convenience)
 * `func_name`: The name of the `step_func` (for convenience)
 * `system_time`: The system time when the step was started

## `[:step_wise, :step, :stop]`

Executed when a step stop with all of the same metadata as the `start` event, but also with:

 * `result`: the value (`{:ok, _}` or `{:error, _}` tuple) that was returned from the step function
 * `success`: (!!TODO!!): A boolean describing if the result was a success (for convenience, based on `result`)

There is also a `duration` as a measurement value to give the total time taken by the step.

# Integration With Your App

## Metrics

If you use `phoenix` you'll get `telemetry_metrics` and a `MyAppWeb.Telemetry` module by default.  In that case you can easily get metrics for all steps that you create:

```elixir
      summary([:step_wise, :step, :stop, :duration],
        unit: {:native, :millisecond},
        tags: [:hostname, :module, :func_name]
      ),
      counter([:step_wise, :step, :stop, :duration],
        unit: {:native, :millisecond},
        tags: [:hostname, :module, :func_name]
      ),
```

## Logging

Here is an example of how you might implement logging for your steps (call `MyApp.StepWiseIntegration.install()` somewhere like your `MyApp.Application.start/2`):

```elixir
defmodule MyApp.StepWiseIntegration do
  def install do
    :telemetry.attach_many(
      __MODULE__,
      [
        [:step_wise, :step, :start],
        [:step_wise, :step, :stop],
      ],
      &__MODULE__.handle/4,
      []
    )
  end

   def handle(
         [:step_wise, :step, :stop],
         %{duration: duration},
         %{module: module, func_name: func_name, result: result},
         _config
       ) do
     case result do
       {:error, exception} ->
         Logger.error(Exception.message(exception))
         # Since `StepWise` wraps all errors, calling `Exception.message` will return
         # information about the if the error was returned/raised and about which
         # step it came from.  In the code above, calling `Exception.message` on a returned
         # exception might give us a string like:
         #   "There was an error *returned* in MyApp.NotifyCommenters.notify_users/1:\n\n\"Email server is not available\""

       {:ok, value} ->
         log_info("#{module}.#{func_name} *succeeded* in #{duration}")
         # You may not choose to log successes if it generates too many logs
     end
   end
end
```

# `StepWise` vs Elixir's `with`

... !!TODO!! ...

The `with` clause in Elixir is a way to specify a pattern-matched ["happy path"](https://en.wikipedia.org/wiki/Happy_path) for a series of expressions.  The first expression which does not match it's corresponding pattern will be either:

 * Returned from the `with` (if no `else` is given)
 * Given to a series of pattern matches (using `else`)
 * 

# `StepWise`

 * `StepWise` uses functions to give identification to steps when something goes wrong.
 * `StepWise` `rescue`s from exceptions and `catch`es throws.
 * `StepWise` emits `telemetry` events to allow implementing meta-behavior (e.g. logs, metrics, and tracing) for processes defined via `StepWise`.
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

# State-Based Usage

Above is a primary use-case of chaining together functions in a pipe-like way (starting with one value and transforming or replacing it as the chain progresses).  In some cases, however, you may want to use a more `GenServer`-like style where you have a state object that is modified along the way:

```elixir
def EmailPost do
  import StepWise

  def run(user_id, post_id) do
    %{user_id: user_id, post_id: post_id}
    |> step(&MyApp.Posts.get_comments/1)
    |> step(&fetch_user_data/1)
    |> step(&fetch_post_data/1)
    |> step(&finalize/1)
  end

  def fetch_user_data(%{user_id: id} = state) do
    {:ok, Map.put(state, :user, MyApp.Users.get(id))}
  end

  def fetch_post_data(%{post_id: id} = state) do
    {:ok, Map.put(state, :post, MyApp.Posts.get(id))}
  end

  def finalize(%{user: user, post: post}) do
    # ...
  end
end
```

Note that `import StepWise` is used here.  The first example used the `StepWise` module explicitly to demonstrate the recommendation from the [Elixir guides](https://elixir-lang.org/getting-started/alias-require-and-import.html#import) to prefer `alias` over `import`.  But in self-contained modules you may find the style of `import` preferable.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/step_wise>.

# TODO TODO TODO

 * Ability to pass in options to signify telemetry metadata

