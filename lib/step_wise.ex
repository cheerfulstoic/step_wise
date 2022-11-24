defmodule StepWise do
  @moduledoc """
  `StepWise` is a library to help you with code which works in a series of steps
  which can each succeed or fail.  It has a few goals:

    * Simplify and improve the readability of such code
    * Provide useful debugging in a few ways:
      * Information on which step failed
      * Values from each step
      * [telemetry](https://github.com/beam-telemetry/telemetry) events for each step as well as the final resolution

  # Usage

    To use `StepWise`, you need to define a module which:

      * ...calls `use StepWise`
      * ...defines at least one function which gives an initial value to a series of steps
      * ...defines functions to implement the steps

    Each function implementing a step gets two arguments:

      * The initial value passed into the pipeline
      * A `Map` with all of the successful results of previous steps

    If a step fails, all steps after will be skipped and the error will be returned.

      defmodule MyApp.UseCase.PublishPost do
        use StepWise

        def steps(post_id, options) do
          %{post_id: post_id, options: options}
          |> step(:mark_as_published)
          |> step(:refresh_cache)
          |> step(:send_emails)
        end

        # You can define a function like this or simply call `StepWise.resolve` outside of the module.
        def resolve(post_id, options) do
          steps(post_id, options)
          |> resolve()
        end


        # Steps can be return success with `{:ok, _}` tuples
        defp mark_as_published(%{post_id: post_id}, _) do
          # ...

          {:ok, updated_post}
        end

        # Simply return `:ok` to return a `nil` result
        def refresh_cache(%{options: options}, %{mark_as_published: post}) do
          MyApp.Posts.refresh_caches_before(post.updated_at, refresh_all: options[:refresh_all])

          :ok
        end

        def send_emails(%{post_id: post_id, options: options}, %{mark_as_published: post}) do
          # `send_updates_for` returns either of the following:
          #   {:ok, sent_emails_count}
          #   {:error, reason}
          MyApp.Email.send_updates_for(post, format: options[:email_format])
        end
      end

    All steps *must*:

      * Return one of: `{:ok, _}`, `:ok`, `{:error, _}`, `:error`
      * Return a `List` of the above (any error results will cause the step to fail)
      * `raise` or `throw` (which will be `rescue`d / `catch`ed and turned into a pipeline error)

    Each call to `step` returns a `StepWise.State` object, so you can either call `resolve` to return
    the ok/error result, or return the `StepWise.State` if you want do:

     * Chain multiple functions together
     * Have control over when `resolve` is called
     * Use the `StepWise.State` object directly to get details of the run.

  # Telemetry

    `StepWise` uses the [telemetry](https://github.com/beam-telemetry/telemetry) package to produce standardized
    events which your app can handle and deal with (creating logs, traces, or metrics for example).

    The following telemetry events are emitted when steps are executed:

      `[:step_wise, :step, :start]` metadata: `system_time`, `id`, `module`, `step_name`
      `[:step_wise, :step, :stop]` measurements: `duration`  metadata: `state`, `id` (same value as `start`), `module`, `step_name`

    The following telemetry event is emitted when `resolve` is called:

      `[:step_wise, :resolve]` metadata: `system_time`, `state`, `resolution`

    The `resolution` value is the result of the `resolve` (either `{:ok, _}` or `{:error, _}`).

    Calling `StepWise.resolve` will cause the above telemetry event to be sent.  If you would just like the value without
    the event, call `StepWise.resolution`.

    # TODO to implement / test:
    #
    # Integration with tracing (datadog)
    # Integration with logging
    # Integration with exception reporting (Sentry)
  """

  defmodule State do
    defstruct ~w[initial_value result step_values]a
  end

  defmodule Error do
    @moduledoc """
      `type` is one of `:tuple`, `:exception`, or `:throw`
    """

    @type t() :: %__MODULE__{
            type: :atom,
            step_name: :atom,
            value: term()
          }

    defexception [:type, :step_name, :value]

    def message(%__MODULE__{step_name: step_name, value: values})
        when is_list(values) do
      error_messages =
        Enum.map(values, fn value ->
          type_specific_message(%__MODULE__{type: :tuple, step_name: step_name, value: value})
        end)

      "Errors in step `#{step_name}`:\n- #{Enum.join(error_messages, "\n- ")}"
    end

    def message(%__MODULE__{step_name: step_name} = exception) do
      "Error in step `#{step_name}`: #{type_specific_message(exception)}"
    end

    # defp type_specific_message(%__MODULE__{type: :tuple, value: %module{} = exception}) do
    #   "#{Macro.to_string(module)}: #{Exception.message(exception)}"
    # end

    defp type_specific_message(%__MODULE__{type: :tuple, value: value}) do
      "#{value}"
    end

    defp type_specific_message(%__MODULE__{type: :exception, value: %module{} = exception}) do
      "#{Macro.to_string(module)}: #{Exception.message(exception)}"
    end

    defp type_specific_message(%__MODULE__{type: :throw, value: value}) do
      "Value thrown: #{inspect(value)}"
    end
  end

  # TODO: Idea:
  # Ability to return {:pass, new_value} to give a new "initial value"
  # Maybe call it something other that "initial value"?

  defmacro __using__(_opts) do
    quote do
      import StepWise, only: [step: 2, resolve: 1]
    end
  end

  defmacro step(state_or_initial_value, step_name) do
    expanded_step_name = Macro.expand_once(step_name, __CALLER__)

    quote do
      state =
        case unquote(state_or_initial_value) do
          %State{initial_value: initial_value, step_values: step_values} = state ->
            state

          initial_value ->
            %State{
              initial_value: initial_value,
              step_values: %{},
              result: {:ok, nil}
            }
        end

      case state.result do
        {:error, _} ->
          state

        {:ok, _} ->
          step_name = unquote(expanded_step_name)

          StepWise.telemetry_step_span(__MODULE__, step_name, fn ->
            result =
              StepWise._result_with_error(fn ->
                unquote(expanded_step_name)(state.initial_value, state.step_values)
              end)

            StepWise.update_state_with_result(state, step_name, result)
          end)
      end
    end
  end

  def update_state_with_result(state, step_name, result) do
    case maybe_collapse_result_list(result) do
      :ok ->
        value = nil

        state
        |> Map.put(:result, {:ok, value})
        |> Map.put(:step_values, Map.put(state.step_values, step_name, value))

      {:ok, value} ->
        state
        |> Map.put(:result, {:ok, value})
        |> Map.put(:step_values, Map.put(state.step_values, step_name, value))

      :error ->
        Map.put(
          state,
          :result,
          {:error, %Error{type: :tuple, step_name: step_name, value: nil}}
        )

      {:error, error} ->
        Map.put(
          state,
          :result,
          {:error, %Error{type: :tuple, step_name: step_name, value: error}}
        )

      {:throw, value} ->
        Map.put(
          state,
          :result,
          {:error,
           %Error{
             type: :throw,
             step_name: step_name,
             value: value
           }}
        )

      {:raise, exception, _stacktrace} ->
        Map.put(
          state,
          :result,
          {:error,
           %Error{
             type: :exception,
             step_name: step_name,
             value: exception
           }}
        )

      other ->
        raise """
          Expected step function `#{step_name}` to return :ok | {:ok, _} | :error | {:error, _}, a list of those terms, or to raise/throw.  Instead it returned:

          #{inspect(other)}
        """
    end
  end

  def resolve(state) do
    resolution = resolution(state)

    :telemetry.execute(
      [:step_wise, :resolve],
      %{},
      %{system_time: System.system_time(), state: state, resolution: resolution}
    )

    resolution
  end

  def resolution(%State{result: {:error, error}}) do
    {:error, Exception.message(error)}
  end

  def resolution(%State{result: {:ok, value}}) do
    {:ok, value}
  end

  def telemetry_step_span(module, step_name, func) do
    id = :erlang.unique_integer()

    :telemetry.span(
      [:step_wise, :step],
      %{system_time: System.system_time(), id: id, module: module, step_name: step_name},
      fn ->
        state = func.()
        {state, %{id: id, module: module, step_name: step_name, state: state}}
      end
    )
  end

  def _result_with_error(func) do
    func.()
  rescue
    exception ->
      {:raise, exception, __STACKTRACE__}
  catch
    value ->
      {:throw, value}
  end

  def maybe_collapse_result_list(list) when is_list(list) do
    list
    |> Enum.split_with(fn
      {:ok, _} ->
        true

      :ok ->
        true

      {:error, _} ->
        false

      :error ->
        false

      other ->
        throw {:unexpected_value, other}
    end)
    |> case do
      {_, [_ | _] = errors} ->
        {:error,
         Enum.map(errors, fn
           {:error, value} -> value
           :error -> nil
         end)}

      {oks, []} ->
        {:ok,
         Enum.map(oks, fn
           {:ok, value} -> value
           :ok -> nil
         end)}

      other ->
        other
    end
  catch
    {:unexpected_value, value} ->
      value
  end

  def maybe_collapse_result_list(result), do: result
end

# defimpl Inspect, for: StepWise.State do
#   import Inspect.Algebra

#   def inspect(state, opts) do
#     # concat(["MapSet.new(", Inspect.List.inspect(MapSet.to_list(map_set), opts), ")"])
#     new_opts = [success: :green, error: :red]

#     opts = Map.update(opts, :syntax_colors, new_opts, &Keyword.merge(&1, new_opts))

#     state
#     |> StepWise.resolution()
#     |> case do
#       {:ok, value} -> [color("SUCCESS: ", :success, opts), to_doc(value, opts)]
#       {:error, message} -> [color("ERROR: #{message}", :error, opts)]
#     end
#     |> concat()
#   end
# end
