defmodule PubQuizzerWeb.MagicLinkController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Accounts

  def show(conn, %{"token" => token}) do
    case Accounts.verify_magic_link(token) do
      {:ok, user} ->
        {:ok, _} = Accounts.sign_in_user(user)

        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Willkommen, #{user.email}!")
        |> redirect(to: "/admin/events")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "Der Login-Link ist abgelaufen. Bitte fordere einen neuen an.")
        |> redirect(to: "/admin/login")

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "Ungültiger Login-Link.")
        |> redirect(to: "/admin/login")
    end
  end

  def show(conn, _params) do
    conn
    |> put_flash(:error, "Ungültiger Login-Link.")
    |> redirect(to: "/admin/login")
  end
end
