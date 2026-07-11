defmodule PubQuizzerWeb.AdminSessionController do
  use PubQuizzerWeb, :controller

  def new(conn, _params) do
    if get_session(conn, :admin) == true do
      redirect(conn, to: "/admin/events")
    else
      conn |> render(:new, flash: %{})
    end
  end

  def create(conn, %{"password" => password}) do
    admin_password = Application.fetch_env!(:pub_quizzer, :admin) |> Keyword.fetch!(:password)

    if password == admin_password do
      conn
      |> put_session(:admin, true)
      |> put_flash(:info, "Willkommen im Administrationsbereich.")
      |> redirect(to: "/admin/events")
    else
      conn
      |> put_flash(:error, "Falsches Kennwort.")
      |> redirect(to: "/admin/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Vom Administrationsbereich abgemeldet.")
    |> redirect(to: "/admin/login")
  end
end
