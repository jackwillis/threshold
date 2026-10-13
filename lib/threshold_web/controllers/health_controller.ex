defmodule ThresholdWeb.HealthController do
  use ThresholdWeb, :controller

  def health(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    case Threshold.Readiness.check() do
      :ok ->
        json(conn, %{status: "ready"})

      {:error, reason} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "not_ready", reason: reason})
    end
  end
end
