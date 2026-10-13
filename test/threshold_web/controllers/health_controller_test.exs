defmodule ThresholdWeb.HealthControllerTest do
  use ThresholdWeb.ConnCase

  setup do
    enabled = Application.get_env(:threshold, :database_enabled)
    name = Application.get_env(:threshold, :default_world)
    graph = Application.get_env(:threshold, :play_graph)

    on_exit(fn ->
      Application.put_env(:threshold, :database_enabled, enabled)
      Application.put_env(:threshold, :default_world, name)

      if graph,
        do: Application.put_env(:threshold, :play_graph, graph),
        else: Application.delete_env(:threshold, :play_graph)
    end)

    :ok
  end

  test "liveness is public and independent of the database", %{conn: conn} do
    Application.put_env(:threshold, :database_enabled, false)
    conn = get(conn, ~p"/healthz")
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "readiness reports an unavailable database without details", %{conn: conn} do
    Application.put_env(:threshold, :database_enabled, false)

    assert conn |> get(~p"/readyz") |> json_response(503) == %{
             "status" => "not_ready",
             "reason" => "database_unavailable"
           }
  end

  describe "database checks" do
    @describetag :database
    setup do
      Ecto.Adapters.SQL.Sandbox.checkout(Threshold.Repo)
      Application.put_env(:threshold, :play_graph, "generated")
      :ok
    end

    test "stopped database repository does not break liveness", %{conn: conn} do
      :ok = Supervisor.terminate_child(Threshold.Supervisor, Threshold.Repo)
      on_exit(fn -> Supervisor.restart_child(Threshold.Supervisor, Threshold.Repo) end)
      assert conn |> get(~p"/healthz") |> json_response(200) == %{"status" => "ok"}

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "database_unavailable"
             }
    end

    test "migrated database and valid fixture world are ready", %{conn: conn} do
      conn = get(conn, ~p"/readyz")
      assert json_response(conn, 200) == %{"status" => "ready"}
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "missing application tables are not ready", %{conn: conn} do
      Ecto.Adapters.SQL.query!(Threshold.Repo, "DROP TABLE completed_interactions")

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "migrations_pending"
             }
    end

    test "missing migration tracking table is not ready", %{conn: conn} do
      Ecto.Adapters.SQL.query!(Threshold.Repo, "DROP TABLE schema_migrations")

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "migrations_pending"
             }
    end

    test "pending migrations are not ready", %{conn: conn} do
      Ecto.Adapters.SQL.query!(
        Threshold.Repo,
        "DELETE FROM schema_migrations WHERE version = 20261010000000"
      )

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "migrations_pending"
             }
    end

    test "malformed scratch world files are not ready", %{conn: conn} do
      original = Application.fetch_env!(:threshold, :worlds_dir)

      scratch =
        Path.join(System.tmp_dir!(), "threshold-health-#{System.unique_integer([:positive])}")

      File.mkdir_p!(scratch)
      File.cp_r!(Path.join(original, "tiny"), Path.join(scratch, "tiny"))
      Application.put_env(:threshold, :worlds_dir, scratch)

      on_exit(fn ->
        Application.put_env(:threshold, :worlds_dir, original)
        File.rm_rf!(scratch)
      end)

      File.write!(Path.join(scratch, "tiny/authored.json"), "private malformed content")

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "world_unavailable"
             }
    end

    test "malformed interactions are not ready", %{conn: conn} do
      original = Application.fetch_env!(:threshold, :worlds_dir)

      scratch =
        Path.join(System.tmp_dir!(), "threshold-health-#{System.unique_integer([:positive])}")

      File.mkdir_p!(scratch)
      File.cp_r!(Path.join(original, "tiny"), Path.join(scratch, "tiny"))
      Application.put_env(:threshold, :worlds_dir, scratch)

      on_exit(fn ->
        Application.put_env(:threshold, :worlds_dir, original)
        File.rm_rf!(scratch)
      end)

      File.write!(Path.join(scratch, "tiny/interactions.json"), "private malformed content")

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "world_unavailable"
             }
    end

    test "invalid configured world is not ready and reveals no path or content", %{conn: conn} do
      Application.put_env(:threshold, :default_world, "missing-private-world")

      assert conn |> get(~p"/readyz") |> json_response(503) == %{
               "status" => "not_ready",
               "reason" => "world_unavailable"
             }
    end
  end
end
