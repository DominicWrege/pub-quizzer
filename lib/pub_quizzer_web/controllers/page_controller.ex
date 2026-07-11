defmodule PubQuizzerWeb.PageController do
  use PubQuizzerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> text("")
  end
end
