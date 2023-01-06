defmodule StepWiseTest do
  use ExUnit.Case, async: false

  # TODO: Test exception when expected value returned from step

  # TODO: Resolve should take a function which returns a final value
  #       or should there just be a final transform which turns a
  #       Map state into a value?

  # TODO: Some way to add handling for failures?
  #
  # TODO: Some way to add cleanup?

  # TODO: Test to cover case of nesting steps inside of one larger step

  # Module which pretentds to get a response from a remote system
  defmodule RemoteSystem do
    def fetch_user(user_id) do
      if user_id >= 0 do
        {:ok, %{"id" => user_id, "username" => "user#{user_id}"}}
      else
        {:error, "Invalid user ID"}
      end
    end

    def fetch_post(post_id) do
      if post_id >= 0 do
        {:ok, %{"id" => post_id}}
      else
        {:error, "Invalid post ID"}
      end
    end
  end

  defmodule EmailPost do
    def steps(value) do
      value
      |> StepWise.step(&fetch_user_data/1)
      |> StepWise.step(&fetch_post_data/1)
      |> StepWise.step(&side_effect/1)
      |> StepWise.step(&throw_if_needed/1)
      |> StepWise.step(&arbitrary_result/1)
      |> StepWise.step(&send_email/1)
    end

    def fetch_user_data(%{user_id: user_id} = state) do
      case RemoteSystem.fetch_user(user_id) do
        {:ok, user_data} ->
          {:ok, Map.put(state, :user_data, user_data)}

        {:error, _} = _error ->
          {:error, "Unable to fetch user #{user_id}"}
      end
    end

    def fetch_post_data(%{post_id: post_id} = state) do
      {:ok, post_data} = RemoteSystem.fetch_post(post_id)

      {:ok, Map.put(state, :post_data, post_data)}
    end

    def side_effect(%{post_id: _post_id}) do
      # Do something that doesn't change the state

      :ok
    end

    def throw_if_needed(state) do
      if state[:throw_it!] do
        throw("Here we throw!")
      end

      {:ok, state}
    end

    def arbitrary_result(state) do
      state[:arbitrary_result_return_value] || {:ok, state}
    end

    def send_email(%{post_id: _post_id} = state) do
      # code that would send email would go here

      {:ok, state}
    end

    def with_integer_guard(i) when is_integer(i) do
      {:ok, i}
    end
  end

  describe ".step" do
    setup do
      :telemetry.attach_many(
        __MODULE__,
        [
          [:step_wise, :step, :start],
          [:step_wise, :step, :stop]
        ],
        fn
          path, measurements, metadata, config ->
            send(self(), {:telemetry, {path, measurements, metadata, config}})
        end,
        []
      )

      on_exit(fn -> :ok = Application.delete_env(:step_wise, :wrap_step_function_errors) end)

      :ok
    end

    test "basic success" do
      assert {:ok,
              %{
                user_id: 123,
                post_id: 456,
                post_data: %{"id" => 456},
                user_data: %{"id" => 123, "username" => "user123"}
              }} =
               {:ok, %{user_id: 123, post_id: 456}}
               |> StepWise.step(&EmailPost.fetch_user_data/1)
               |> StepWise.step(&EmailPost.fetch_post_data/1)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, step_func: _, module: EmailPost, func_name: :fetch_user_data, system_time: _},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _, monotonic_time: _},
          %{
            id: _,
            system_time: _,
            step_func: _,
            module: EmailPost,
            func_name: :fetch_user_data,
            result:
              {:ok,
               %{post_id: 456, user_data: %{"id" => 123, "username" => "user123"}, user_id: 123}}
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, step_func: _, module: EmailPost, func_name: :fetch_post_data, system_time: _},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _, monotonic_time: _},
          %{
            id: _,
            system_time: _,
            step_func: _,
            module: EmailPost,
            func_name: :fetch_post_data,
            result:
              {:ok,
               %{
                 post_id: 456,
                 user_data: %{"id" => 123, "username" => "user123"},
                 post_data: %{"id" => 456},
                 user_id: 123
               }},
            success: true
          },
          []
        }
      }
    end

    test "first step fails" do
      {:error, %StepWise.StepFunctionError{func: error_func, value: value} = exception} =
        {:ok, %{user_id: -1, post_id: 456}}
        |> StepWise.step(&EmailPost.fetch_user_data/1)
        |> StepWise.step(&EmailPost.fetch_post_data/1)
        |> StepWise.step(&EmailPost.send_email/1)

      assert value == "Unable to fetch user -1"
      assert_func_match(EmailPost, :fetch_user_data, error_func)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _, monotonic_time: _},
          %{
            id: _,
            system_time: _,
            step_func: _,
            module: EmailPost,
            func_name: :fetch_user_data,
            result: {:error, _},
            success: false
          },
          []
        }
      }
    end

    test "configured to not wrap errors" do
      :ok = Application.put_env(:step_wise, :wrap_step_function_errors, false)

      {:error, value} =
        {:ok, %{user_id: -1, post_id: 456}}
        |> StepWise.step(&EmailPost.fetch_user_data/1)
        |> StepWise.step(&EmailPost.fetch_post_data/1)
        |> StepWise.step(&EmailPost.send_email/1)

      assert value == "Unable to fetch user -1"
    end

    test "Exception.message" do
      defmodule ErrorTest do
        def raise_exception(_), do: raise("UP")
        def return_error(_), do: {:error, "OUT"}
      end

      {:error, exception} = StepWise.step({:ok, nil}, &ErrorTest.raise_exception/1)

      assert Exception.message(exception) ==
               "There was an error *raised* in StepWiseTest.ErrorTest.raise_exception/1:\n\n** (Elixir.RuntimeError) UP"

      {:error, exception} = StepWise.step({:ok, nil}, &ErrorTest.return_error/1)

      assert Exception.message(exception) ==
               "There was an error *returned* in StepWiseTest.ErrorTest.return_error/1:\n\n\"OUT\""
    end

    test "middle step raises exception" do
      {:error, %StepWise.StepFunctionError{func: error_func, value: value}} =
        {:ok, %{user_id: 123, post_id: -1}}
        |> StepWise.step(&EmailPost.fetch_user_data/1)
        |> StepWise.step(&EmailPost.fetch_post_data/1)
        |> StepWise.step(fn _ -> {:ok, nil} end)

      assert %MatchError{term: {:error, "Invalid post ID"}} = value
      assert_func_match(EmailPost, :fetch_post_data, error_func)
    end

    test "middle step raises exception (no wrapping)" do
      Application.put_env(:step_wise, :wrap_step_function_errors, false)

      assert_raise MatchError,
                   "no match of right hand side value: {:error, \"Invalid post ID\"}",
                   fn ->
                     {:ok, %{user_id: 123, post_id: -1}}
                     |> StepWise.step(&EmailPost.fetch_user_data/1)
                     |> StepWise.step(&EmailPost.fetch_post_data/1)
                     |> StepWise.step(fn _ -> {:ok, nil} end)
                   end
    end

    test "pattern match can't be found in step function" do
      func = fn %{does_not_exist: value} ->
        {:ok, value}
      end

      {:error, %StepWise.StepFunctionError{func: error_func, value: value} = error} =
        {:ok, %{user_id: 123, post_id: -1}}
        |> StepWise.step(func)

      assert %FunctionClauseError{function: func} = value
    end

    test "FunctionClauseError" do
      {:error,
       %StepWise.StepFunctionError{func: _error_func, value: value, stacktrace: stacktrace}} =
        {:ok, %{user_id: 123, post_id: -1}}
        |> StepWise.step(fn _ -> {:ok, EmailPost.with_integer_guard(:atom)} end)
        |> StepWise.step(fn _ -> {:ok, nil} end)

      assert %FunctionClauseError{
               module: StepWiseTest.EmailPost,
               function: :with_integer_guard,
               arity: 1
             } = value

      # The stacktrace, especially the first line, is important because it is used by
      # FunctionClauseError.blame/2 to output more detail about the error
      assert {EmailPost, :with_integer_guard, [:atom], [file: 'test/step_wise_test.exs', line: _]} =
               List.first(stacktrace)

      # TODO:
      # Having steps inside of the test is good, but need to have tests
      # that check that we get the right function listed here:
      # assert_func_match(EmailPost, :fetch_post_data, error_func)
    end

    test "middle step throws" do
      {:error, %StepWise.StepFunctionError{func: error_func, value: value}} =
        {:ok, %{user_id: 123, post_id: 456, throw_it!: true}}
        |> EmailPost.steps()

      assert value == "Value was thrown: \"Here we throw!\""
      assert_func_match(EmailPost, :throw_if_needed, error_func)
    end

    test "middle step throws (no wrapping)" do
      Application.put_env(:step_wise, :wrap_step_function_errors, false)

      catch_throw(
        {:ok, %{user_id: 123, post_id: 456, throw_it!: true}}
        |> EmailPost.steps()
      ) == "Here we throw!"
    end

    test "initial step is given an error" do
      {:error, %StepWise.Error{func: error_func, message: error_message}} =
        {:error, :initial_error}
        |> EmailPost.steps()

      assert error_message == "Error passed to step: :initial_error"
      assert_func_match(EmailPost, :fetch_user_data, error_func)
    end

    test "initial step is given an error (no wrapping)" do
      Application.put_env(:step_wise, :wrap_step_function_errors, false)

      {:error, reason} =
        {:error, :initial_error}
        |> EmailPost.steps()

      assert reason == :initial_error
    end

    test "step isn't given an :ok or :error value" do
      {:error, %StepWise.Error{func: error_func, message: error_message}} =
        :not_ok_or_error
        |> EmailPost.steps()

      assert error_message ==
               "Value other than {:ok, _} or {:error, _} given to step/2 function: :not_ok_or_error"

      assert_func_match(EmailPost, :fetch_user_data, error_func)
    end

    test "middle step doesn't return :ok or :error result" do
      {:error, %StepWise.Error{func: error_func, message: error_message}} =
        {:ok, %{user_id: 123, post_id: 345, arbitrary_result_return_value: :not_ok_or_error}}
        |> EmailPost.steps()

      assert error_message ==
               "Value other than {:ok, _} or {:error, _} returned for step function: :not_ok_or_error"

      assert_func_match(EmailPost, :arbitrary_result, error_func)
    end

    def assert_func_match(expected_module, expected_name, actual_func) do
      info = Function.info(actual_func)

      assert info[:name] in [expected_name, :"-fun.#{expected_name}/1-"]
      assert info[:module] == expected_module
    end
  end

  describe ".map_step" do
    test "invalid value given" do
      {:error, %StepWise.Error{func: _error_func, message: error_message}} =
        StepWise.map_step([1, 2, 3, 4, 5], fn _ -> :something_else end)

      assert error_message ==
               "Value other than {:ok, _} or {:error, _} given to map_step/2 function: [1, 2, 3, 4, 5]"
    end

    test "basic success" do
      result =
        {:ok, [1, 2, 3, 4, 5]}
        |> StepWise.map_step(fn i -> {:ok, i * 2} end)

      assert result == {:ok, [2, 4, 6, 8, 10]}
    end

    test "basic error results cases" do
      {:error, %StepWise.StepFunctionError{func: _error_func, value: value}} =
        {:ok, [1, 2, 3, 4, 5]}
        |> StepWise.map_step(fn _ -> {:error, "Always fails"} end)

      assert value == "Always fails"

      {:error, %StepWise.StepFunctionError{func: _error_func, value: value}} =
        {:ok, [1, 2, 3, 4, 5]}
        |> StepWise.map_step(fn i ->
          if i >= 3 do
            {:error, "Fails half-way"}
          else
            {:ok, i * 2}
          end
        end)

      assert value == "Fails half-way"
    end

    test "exceptions" do
      {:error, %StepWise.StepFunctionError{func: _error_func, value: value}} =
        {:ok, [1, 2, 3, 4, 5]}
        |> StepWise.map_step(fn _ ->
          raise "Always fails"
        end)

      assert %RuntimeError{message: "Always fails"} = value
    end

    test "invalid return" do
      {:error, %StepWise.Error{func: _error_func, message: error_message}} =
        {:ok, [1, 2, 3, 4, 5]}
        |> StepWise.map_step(fn _ -> :something_else end)

      assert error_message ==
               "Value other than {:ok, _} or {:error, _} returned for step function: :something_else"
    end
  end
end
