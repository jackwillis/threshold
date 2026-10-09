defmodule ThresholdWeb.PageController do
  use ThresholdWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
