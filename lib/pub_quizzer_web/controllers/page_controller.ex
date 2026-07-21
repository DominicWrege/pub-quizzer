defmodule PubQuizzerWeb.PageController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Accounts
  alias PubQuizzer.Accounts.User

  def home(conn, _params) do
    case load_current_scope(conn) do
      %{user: _user} ->
        redirect(conn, to: "/admin/events")

      nil ->
        render(conn, :home, current_scope: nil, load_live_socket?: false)
    end
  end

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> text("")
  end

  defp load_current_scope(conn) do
    case get_session(conn, :user_id) do
      nil ->
        nil

      user_id ->
        case Accounts.get_user(user_id) do
          %User{active: true} = user -> %{user: user}
          _ -> nil
        end
    end
  end
end
