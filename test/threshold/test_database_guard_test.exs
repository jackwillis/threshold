defmodule Threshold.TestDatabaseGuardTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @variables ~w(THRESHOLD_TEST_DATABASE_URL THRESHOLD_DATABASE_URL)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  defp read_with(name) do
    System.put_env("THRESHOLD_TEST_DATABASE_URL", "postgres://u:p@localhost:5433/#{name}")
    Config.Reader.read!(@runtime, env: :test, target: :host)
  end

  test "accepts the documented and parallel scratch test database names" do
    for name <-
          ~w(threshold_test threshold_test_34 threshold_test_demo my_scratch_test my-scratch_test MY_scratch_test) do
      assert read_with(name)[:threshold][:database_enabled], name
    end
  end

  test "rejects the development database and look-alike names" do
    for name <- ~w(threshold_game threshold threshold_testing threshold_test34 threshold_test_Bad) do
      assert_raise RuntimeError, ~r/dedicated test database/, fn -> read_with(name) end
    end
  end
end
