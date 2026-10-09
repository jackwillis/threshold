defmodule ThresholdWeb.EditorLive do
  @moduledoc "Map editor shell. The map itself is owned by the `MapEditor` JS hook (assets/src/hooks)."
  use ThresholdWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Editor")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="map" phx-hook="MapEditor" phx-update="ignore" style="height: 70vh; width: 100%;"></div>
    </Layouts.app>
    """
  end
end
