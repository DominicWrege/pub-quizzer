defmodule PubQuizzerWeb.AdminSessionController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Accounts

  def new(conn, _params) do
    if Accounts.has_users?() do
      case get_session(conn, :user_id) do
        nil ->
          conn
          |> put_resp_header("cache-control", "private, max-age=10800")
          |> render(:new)

        user_id ->
          case Accounts.get_user(user_id) do
            %PubQuizzer.Accounts.User{active: true} ->
              redirect(conn, to: "/admin/topics")

            _ ->
              conn
              |> clear_session()
              |> put_resp_header("cache-control", "private, max-age=10800")
              |> render(:new)
          end
      end
    else
      redirect(conn, to: "/setup")
    end
  end

  def create(conn, %{"email" => email}) do
    # Use the configured endpoint URL rather than the request host so a spoofed
    # Host header can't redirect magic-link emails to an attacker-controlled domain.
    base_url = PubQuizzerWeb.Endpoint.url()

    case Accounts.deliver_magic_link(email, base_url) do
      {:ok, _url} ->
        conn
        |> render(:link_sent, email: email)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, %{message: "E-Mail-Adresse nicht gefunden.", duration: 5000})
        |> redirect(to: "/admin/login")
    end
  end

  def status(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{authenticated: get_session(conn, :user_id) != nil})
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Abgemeldet.")
    |> redirect(to: "/admin/login")
  end
end
