defmodule Threshold.ReleaseConfigTest do
  use ExUnit.Case, async: false

  @variables ~w(SECRET_KEY_BASE THRESHOLD_DATABASE_URL THRESHOLD_TEST_DATABASE_URL PHX_HOST PORT PHX_BIND_ADDRESS POOL_SIZE PHX_SERVER THRESHOLD_WORLDS_DIR)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  defp read(env \\ :prod), do: Config.Reader.read!(@runtime, env: env, target: :host)

  defp credentials do
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))
    System.put_env("THRESHOLD_DATABASE_URL", "postgres://example.invalid/release_test")
  end

  test "reports every missing required production variable together" do
    assert_raise RuntimeError,
                 "Missing required production environment variables: SECRET_KEY_BASE, THRESHOLD_DATABASE_URL",
                 fn -> read() end

    System.put_env("SECRET_KEY_BASE", "")
    assert_raise RuntimeError, ~r/SECRET_KEY_BASE, THRESHOLD_DATABASE_URL/, fn -> read() end
  end

  test "production defaults to loopback and does not start HTTP unless enabled" do
    credentials()
    config = read()[:threshold]
    endpoint = config[ThresholdWeb.Endpoint]
    assert endpoint[:http] == [ip: {127, 0, 0, 1}, port: 4000]
    assert endpoint[:url] == [host: "localhost", port: 4000, scheme: "http"]
    assert endpoint[:server] == false
    assert config[:database_enabled]
    assert config[Threshold.Repo][:pool_size] == 5
  end

  test "production reads host, port, IPv6 bind address, pool, worlds and server" do
    credentials()

    System.put_env(%{
      "PHX_HOST" => "threshold.example",
      "PORT" => "4123",
      "PHX_BIND_ADDRESS" => "::1",
      "POOL_SIZE" => "8",
      "PHX_SERVER" => "true",
      "THRESHOLD_WORLDS_DIR" => "/tmp/release-worlds"
    })

    config = read()[:threshold]
    endpoint = config[ThresholdWeb.Endpoint]
    assert endpoint[:http] == [ip: {0, 0, 0, 0, 0, 0, 0, 1}, port: 4123]
    assert endpoint[:url] == [host: "threshold.example", port: 4123, scheme: "http"]
    assert endpoint[:server]
    assert config[:worlds_dir] == "/tmp/release-worlds"
    assert config[Threshold.Repo][:pool_size] == 8
    assert config[Threshold.Repo][:url] == "postgres://example.invalid/release_test"
  end

  test "rejects malformed production settings with their variable names" do
    credentials()

    for {name, value} <- [
          {"PORT", "0"},
          {"PORT", "65536"},
          {"POOL_SIZE", "no"},
          {"PHX_BIND_ADDRESS", "hostname"},
          {"PHX_SERVER", "yes"}
        ] do
      System.put_env(name, value)
      assert_raise RuntimeError, ~r/#{name}/, fn -> read() end
      System.delete_env(name)
    end
  end

  test "development and test still allow the editor without a database" do
    for env <- [:dev, :test] do
      config = read(env)[:threshold]
      refute config[:database_enabled]
      refute config[Threshold.Repo]
    end
  end
end
