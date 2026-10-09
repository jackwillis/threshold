defmodule ThresholdWeb.Router do
  use ThresholdWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThresholdWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ThresholdWeb do
    pipe_through :browser

    live "/", EditorLive
    get "/worlds/:world/:layer", WorldController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", ThresholdWeb do
  #   pipe_through :api
  # end
end
