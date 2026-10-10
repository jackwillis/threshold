defmodule ThresholdWeb.AtlasLive do
  @moduledoc """
  Classic Atlas visual prototype: the real Madison geography in the atlas style, with one-hop
  markers computed in the browser from the authored connections. It changes nothing and runs no
  game rules; `/play` is untouched. Season is a client display preference (`?season=`).
  """
  use ThresholdWeb, :live_view

  alias Threshold.World

  @seasons ~w(spring summer autumn winter)

  @impl true
  def mount(params, _session, socket) do
    name = if World.valid_name?(params["world"]), do: params["world"], else: World.default_name()

    generation =
      with {:ok, world} <- World.load(name), do: world.generation

    {:ok,
     assign(socket,
       world_name: name,
       generation: if(is_binary(generation), do: generation),
       seasons: @seasons
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} mode="play">
      <div
        id="atlas"
        phx-hook="AtlasPrototype"
        data-world={@world_name}
        data-snapshot={@generation}
        class="atlas"
      >
        <div id="atlas-canvas" phx-update="ignore"></div>
        <div class="atlas-title">
          <h1>Madison</h1>
          <p id="atlas-here"></p>
        </div>
        <div class="atlas-seasons" role="group" aria-label="Season">
          <button :for={season <- @seasons} type="button" data-season={season} aria-pressed="false">
            {season}
          </button>
        </div>
        <p id="atlas-error" class="atlas-error" role="alert"></p>
      </div>
    </Layouts.app>
    """
  end
end
