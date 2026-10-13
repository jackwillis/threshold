defmodule ThresholdWeb.HomeController do
  use ThresholdWeb, :controller

  def index(conn, _params), do: render(conn, :index, page_title: "Welcome")
end
