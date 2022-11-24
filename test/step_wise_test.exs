defmodule StepWiseTest do
  use ExUnit.Case, async: true

  # TODO: Test exception when expected value returned from step

  defmodule Example do
    use StepWise

    def basic_success(value) do
      step(value, :succeed_with_value)
    end

    def basic_success_without_value(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
    end

    def error_at_end(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
      |> step(:error_with_value)
    end

    def error_in_middle(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
      |> step(:error_with_value)
      |> step(:succeed_without_value2)
      |> step(:succeed_with_value2)
    end

    def raise_in_middle(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
      |> step(:raise_it)
      |> step(:succeed_without_value2)
      |> step(:succeed_with_value2)
    end

    def throw_in_middle(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
      |> step(:throw_it)
      |> step(:succeed_without_value2)
      |> step(:succeed_with_value2)
    end

    def everything_without_errors(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
      |> step(:succeed_without_value2)
      |> step(:succeed_with_value2)
    end

    def everything_with_total_using_previous_step(value) do
      value
      |> step(:succeed_with_value)
      |> step(:succeed_without_value)
      |> step(:succeed_without_value2)
      |> step(:succeed_with_value_using_previous_step)
    end

    def list_of_successes(value) do
      step(value, :successful_list)
    end

    def list_of_mixed_successes(value) do
      step(value, :mixed_success_list)
    end

    def successful_list(_, _) do
      [
        {:ok, 1},
        {:ok, 2},
        {:ok, 3},
        {:ok, 4},
        {:ok, 5}
      ]
    end

    def mixed_success_list(_, _) do
      [
        {:ok, 1},
        {:ok, 2},
        {:ok, 3},
        {:error, "Four what??"},
        {:ok, 5},
        {:error, "Six what??"}
      ]
    end

    def succeed_with_value(value, _) do
      {:ok, value + 4}
    end

    def succeed_without_value(_, _) do
      :ok
    end

    def error_with_value(value, _) do
      {:error, "What is a #{value}, even?"}
    end

    def raise_it(value, _) do
      raise "Raise your #{value}!"
    end

    def throw_it(value, _) do
      throw "Here!  Have a #{value}!"
    end

    def succeed_with_value2(value, _) do
      {:ok, value - 3}
    end

    def succeed_with_value_using_previous_step(_, %{succeed_with_value: value}) do
      {:ok, value - 3}
    end

    def succeed_without_value2(_, _) do
      :ok
    end
  end

  describe "steps" do
    setup do
      :telemetry.attach_many(
        __MODULE__,
        [
          [:step_wise, :step, :start],
          [:step_wise, :step, :stop],
          [:step_wise, :resolve]
        ],
        fn
          path, measurements, metadata, config ->
            send(self(), {:telemetry, {path, measurements, metadata, config}})
        end,
        []
      )

      :ok
    end

    test "basic success" do
      state = Example.basic_success(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_with_value},
          []
        }
      }

      final_expected_state = %StepWise.State{
        initial_value: 3,
        result: {:ok, 7},
        step_values: %{succeed_with_value: 7}
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_with_value,
            state: ^final_expected_state
          },
          []
        }
      }

      assert {:ok, 7} = StepWise.resolve(state)

      assert state.step_values == %{succeed_with_value: 7}

      assert_received {
        :telemetry,
        {
          [:step_wise, :resolve],
          %{system_time: _},
          %{state: ^final_expected_state, resolution: {:ok, 7}},
          []
        }
      }
    end

    test "basic success without value" do
      state = Example.basic_success_without_value(3)

      assert state.step_values == %{succeed_with_value: 7, succeed_without_value: nil}

      assert {:ok, nil} = StepWise.resolve(state)
    end

    test "error at the end" do
      state = Example.error_at_end(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_with_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_with_value,
            state: %StepWise.State{
              initial_value: 3,
              result: {:ok, 7},
              step_values: %{succeed_with_value: 7}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_without_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_without_value,
            state: %StepWise.State{
              initial_value: 3,
              result: {:ok, nil},
              step_values: %{succeed_with_value: 7, succeed_without_value: nil}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :error_with_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :error_with_value,
            state: %StepWise.State{
              initial_value: 3,
              result:
                {:error,
                 %StepWise.Error{step_name: :error_with_value, value: "What is a 3, even?"}},
              step_values: %{succeed_with_value: 7, succeed_without_value: nil}
            }
          },
          []
        }
      }

      assert state.step_values == %{succeed_with_value: 7, succeed_without_value: nil}

      assert {:error, "Error in step `error_with_value`: What is a 3, even?"} =
               StepWise.resolve(state)
    end

    test "error in the middle" do
      state = Example.error_in_middle(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_with_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_with_value,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7},
              result: {:ok, 7}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_without_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_without_value,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7, succeed_without_value: nil},
              result: {:ok, nil}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :error_with_value},
          []
        }
      }

      final_expected_state = %StepWise.State{
        initial_value: 3,
        step_values: %{succeed_with_value: 7, succeed_without_value: nil},
        result:
          {:error,
           %StepWise.Error{
             type: :tuple,
             step_name: :error_with_value,
             value: "What is a 3, even?"
           }}
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :error_with_value,
            state: ^final_expected_state
          },
          []
        }
      }

      refute_received {:step, :start, %{}, %{step_name: :succeed_without_value2}}
      refute_received {:step, :stop, %{}, %{step_name: :succeed_without_value2}}
      refute_received {:step, :start, %{}, %{step_name: :succeed_with_value2}}
      refute_received {:step, :stop, %{}, %{step_name: :succeed_with_value2}}

      assert state.step_values == %{succeed_with_value: 7, succeed_without_value: nil}

      assert {:error, "Error in step `error_with_value`: What is a 3, even?"} =
               StepWise.resolve(state)

      assert_received {
        :telemetry,
        {
          [:step_wise, :resolve],
          %{system_time: _},
          %{
            state: ^final_expected_state,
            resolution: {:error, "Error in step `error_with_value`: What is a 3, even?"}
          },
          []
        }
      }
    end

    test "raise in the middle" do
      state = Example.raise_in_middle(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_with_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_with_value,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7},
              result: {:ok, 7}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_without_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_without_value,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7, succeed_without_value: nil},
              result: {:ok, nil}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :raise_it},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :raise_it,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7, succeed_without_value: nil},
              result:
                {:error,
                 %StepWise.Error{
                   step_name: :raise_it,
                   value: %RuntimeError{message: "Raise your 3!"}
                 }}
            }
          },
          []
        }
      }

      refute_received {:step, :start, %{}, %{step_name: :succeed_without_value2}}
      refute_received {:step, :stop, %{}, %{step_name: :succeed_without_value2}}
      refute_received {:step, :start, %{}, %{step_name: :succeed_with_value2}}
      refute_received {:step, :stop, %{}, %{step_name: :succeed_with_value2}}

      assert state.step_values == %{succeed_with_value: 7, succeed_without_value: nil}

      assert {:error, "Error in step `raise_it`: RuntimeError: Raise your 3!"} =
               StepWise.resolve(state)
    end

    test "throw in the middle" do
      state = Example.throw_in_middle(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_with_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_with_value,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7},
              result: {:ok, 7}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :succeed_without_value},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :succeed_without_value,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7, succeed_without_value: nil},
              result: {:ok, nil}
            }
          },
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :throw_it},
          []
        }
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :throw_it,
            state: %StepWise.State{
              initial_value: 3,
              step_values: %{succeed_with_value: 7, succeed_without_value: nil},
              result: {:error, %StepWise.Error{step_name: :throw_it, value: "Here!  Have a 3!"}}
            }
          },
          []
        }
      }

      refute_received {:step, :start, %{}, %{step_name: :succeed_without_value2}}
      refute_received {:step, :stop, %{}, %{step_name: :succeed_without_value2}}
      refute_received {:step, :start, %{}, %{step_name: :succeed_with_value2}}
      refute_received {:step, :stop, %{}, %{step_name: :succeed_with_value2}}

      assert state.step_values == %{succeed_with_value: 7, succeed_without_value: nil}

      assert {:error, "Error in step `throw_it`: Value thrown: \"Here!  Have a 3!\""} =
               StepWise.resolve(state)
    end

    test "everything without errors" do
      state = Example.everything_without_errors(3)

      assert state.step_values == %{
               succeed_with_value: 7,
               succeed_without_value: nil,
               succeed_without_value2: nil,
               succeed_with_value2: 0
             }

      assert {:ok, 0} = StepWise.resolve(state)
    end

    test "everything without errors using previous step" do
      state = Example.everything_with_total_using_previous_step(3)

      assert state.step_values == %{
               succeed_with_value: 7,
               succeed_without_value: nil,
               succeed_without_value2: nil,
               succeed_with_value_using_previous_step: 4
             }

      assert {:ok, 4} = StepWise.resolve(state)
    end

    test "returning a list of successes" do
      state = Example.list_of_successes(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :successful_list},
          []
        }
      }

      final_expected_state = %StepWise.State{
        initial_value: 3,
        step_values: %{successful_list: [1, 2, 3, 4, 5]},
        result: {:ok, [1, 2, 3, 4, 5]}
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :successful_list,
            state: ^final_expected_state
          },
          []
        }
      }

      assert state.step_values == %{
               successful_list: [1, 2, 3, 4, 5]
             }

      assert {:ok, [1, 2, 3, 4, 5]} = StepWise.resolve(state)

      assert_received {
        :telemetry,
        {
          [:step_wise, :resolve],
          %{system_time: _},
          %{state: ^final_expected_state, resolution: {:ok, [1, 2, 3, 4, 5]}},
          []
        }
      }
    end

    test "returning a list of mixed success" do
      state = Example.list_of_mixed_successes(3)

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :start],
          %{system_time: _},
          %{id: _, module: StepWiseTest.Example, step_name: :mixed_success_list},
          []
        }
      }

      final_expected_state = %StepWise.State{
        initial_value: 3,
        step_values: %{},
        result:
          {:error,
           %StepWise.Error{
             type: :tuple,
             step_name: :mixed_success_list,
             value: ["Four what??", "Six what??"]
           }}
      }

      assert_received {
        :telemetry,
        {
          [:step_wise, :step, :stop],
          %{duration: _},
          %{
            id: _,
            module: StepWiseTest.Example,
            step_name: :mixed_success_list,
            state: ^final_expected_state
          },
          []
        }
      }

      assert state.step_values == %{}

      assert {:error, "Errors in step `mixed_success_list`:\n- Four what??\n- Six what??"} =
               StepWise.resolve(state)

      assert_received {
        :telemetry,
        {
          [:step_wise, :resolve],
          %{system_time: _},
          %{
            state: ^final_expected_state,
            resolution:
              {:error, "Errors in step `mixed_success_list`:\n- Four what??\n- Six what??"}
          },
          []
        }
      }
    end
  end

  # TODO:
  # * combine two functions
end
