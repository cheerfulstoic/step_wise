defmodule StepWise do
  # TODO: Implement behavior?

  defmodule Error do
    @moduledoc "For errors returned by StepWise"

    @type t() :: %__MODULE__{
            func: function(),
            message: term()
          }

    defexception [:func, :message]

    @impl true
    def exception({func, message}) do
      %__MODULE__{func: func, message: message}
    end

    @impl true
    def message(exception) do
      function_info = Function.info(exception.func)

      "[#{inspect(function_info[:module])} | #{function_info[:name]}] #{exception.message}"
    end
  end

  defmodule StepFunctionError do
    @moduledoc "For errors returned / raised / thrown in step functions"

    @type t() :: %__MODULE__{
            func: function(),
            value: term(),
            stacktrace: Exception.stacktrace(),
            raised?: boolean()
          }

    defexception [:func, :value, :stacktrace, :raised?]

    @impl true
    def exception({func, error_value, stacktrace, raised?}) do
      %__MODULE__{func: func, value: error_value, stacktrace: stacktrace, raised?: raised?}
    end

    @impl true
    def message(%{func: func, value: value, raised?: raised?}) do
      function_info = Function.info(func)

      {message, exception_info} =
        if Exception.exception?(value) do
          {Exception.message(value), "** (#{value.__struct__}) "}
        else
          {inspect(value), nil}
        end

      raised_or_returned = if(raised?, do: "raised", else: "returned")

      "There was an error *#{raised_or_returned}* in #{inspect(function_info[:module])}.#{function_info[:name]}/1:\n\n#{exception_info}#{message}"
    end

    @impl true
    def blame(%{func: _func, value: value} = exception, stacktrace) do
      if Exception.exception?(value) do
        {origin_exception, origin_stacktrace} =
          Exception.blame(:error, value, exception.stacktrace)

        {Map.put(exception, :value, origin_exception), origin_stacktrace}
      else
        {exception, stacktrace}
      end
    end
  end

  # TODO: Handle `exit`.  Other things?
  # https://tylerpachal.medium.com/error-handling-in-elixir-rescue-vs-catch-946e052db97b
  def step({:ok, state}, func) do
    telemetry_step_span(func, fn ->
      result =
        try do
          func.(state)
        rescue
          exception ->
            if wrap_step_function_errors?() do
              {:error, StepFunctionError.exception({func, exception, __STACKTRACE__, true})}
            else
              reraise exception, __STACKTRACE__
            end
        catch
          :throw, value ->
            if wrap_step_function_errors?() do
              {:error, "Value was thrown: #{inspect(value)}"}
            else
              throw(value)
            end
        end

      case result do
        {:ok, new_state} ->
          {:ok, new_state}

        :ok ->
          {:ok, state}

        {:error, %StepFunctionError{}} = error ->
          error

        {:error, error_value} ->
          if wrap_step_function_errors?() do
            {:error, StepFunctionError.exception({func, error_value, nil, false})}
          else
            {:error, error_value}
          end

        other ->
          {:error,
           Error.exception(
             {func,
              "Value other than {:ok, _} or {:error, _} returned for step function: #{inspect(other)}"}
           )}
      end
    end)
  end

  def step({:error, %exception_mod{} = exception}, _func)
      when exception_mod in [Error, StepFunctionError] do
    {:error, exception}
  end

  def step({:error, value}, func) do
    if wrap_step_function_errors?() do
      {:error, Error.exception({func, "Error passed to step: #{inspect(value)}"})}
    else
      {:error, value}
    end
  end

  def step(other, func) do
    {:error,
     Error.exception(
       {func,
        "Value other than {:ok, _} or {:error, _} given to step/2 function: #{inspect(other)}"}
     )}
  end

  defp wrap_step_function_errors? do
    Application.get_env(:step_wise, :wrap_step_function_errors, true)
  end

  defp telemetry_step_span(step_func, func) do
    function_info = Function.info(step_func)

    module = function_info[:module]
    func_name = function_info[:name]

    id = :erlang.unique_integer()

    :telemetry.span(
      [:step_wise, :step],
      %{
        system_time: System.system_time(),
        id: id,
        step_func: step_func,
        module: module,
        func_name: func_name
      },
      fn ->
        result = func.()

        {result,
         %{
           id: id,
           system_time: System.system_time(),
           step_func: step_func,
           module: module,
           func_name: func_name,
           result: result,
           success: success_result?(result)
         }}
      end
    )
  end

  def success_result?({:ok, _}), do: true
  def success_result?({:error, _}), do: false

  def map_step({:ok, enum}, func) do
    Enum.reduce(enum, {:ok, []}, fn
      item, {:ok, result} ->
        with {:ok, value} <- step({:ok, item}, func) do
          {:ok, [value | result]}
        end

      _item, {:error, _} = error ->
        error
    end)
    |> case do
      {:ok, result} ->
        {:ok, Enum.reverse(result)}

      {:error, _} = error ->
        error
    end
  end

  def map_step({:error, _} = error, func), do: step(error, func)

  def map_step(other, func) do
    {:error,
     Error.exception(
       {func,
        "Value other than {:ok, _} or {:error, _} given to map_step/2 function: #{inspect(other)}"}
     )}
  end
end
