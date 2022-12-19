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
    def blame(%{func: func, value: value} = exception, stacktrace) do
      if Exception.exception?(value) do
        # {origin_exception, origin_stacktrace} = value.__struct__.blame(value, exception.stacktrace)
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
    result =
      try do
        func.(state)
      rescue
        exception ->
          {:error, StepFunctionError.exception({func, exception, __STACKTRACE__, true})}
      catch
        :throw, value ->
          {:error, "Value was thrown: #{inspect(value)}"}
      end

    case result do
      {:ok, new_state} ->
        {:ok, new_state}

      :ok ->
        {:ok, state}

      {:error, %StepFunctionError{}} = error ->
        error

      {:error, error_value} ->
        {:error, StepFunctionError.exception({func, error_value, nil, false})}

      other ->
        {:error,
         Error.exception(
           {func,
            "Value other than {:ok, _} or {:error, _} returned for step function: #{inspect(other)}"}
         )}
    end
  end

  def step({:error, %exception_mod{} = exception}, _func)
      when exception_mod in [Error, StepFunctionError] do
    {:error, exception}
  end

  def step({:error, value}, func) do
    {:error, Error.exception({func, "Error given to initial step: #{inspect(value)}"})}
  end

  def step(other, func) do
    {:error,
     Error.exception(
       {func,
        "Value other than {:ok, _} or {:error, _} given to step/2 function: #{inspect(other)}"}
     )}
  end

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

  def resolve({:error, %exception_mod{} = exception})
      when exception_mod in [Error, StepFunctionError] do
    {:error, exception}
  end

  def resolve({:ok, value}), do: {:ok, value}

  def resolve!(result) do
    case resolve(result) do
      {:ok, value} ->
        value

      {:error, exception} ->
        raise exception
    end
  end
end
