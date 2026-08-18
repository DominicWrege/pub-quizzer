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
    case Accounts.deliver_login_code(email) do
      {:ok, _code} ->
        conn
        |> render(:code_entry, email: email, error: nil)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, %{message: "E-Mail-Adresse nicht gefunden.", duration: 5000})
        |> redirect(to: "/admin/login")
    end
  end

  def create(conn, _params), do: redirect(conn, to: "/admin/login")

  def verify(conn, %{"email" => email, "code" => code}) do
    case Accounts.verify_login_code(email, code) do
      {:ok, user} ->
        {:ok, _} = Accounts.sign_in_user(user)

        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Willkommen, #{user.name}!")
        |> redirect(to: "/admin/topics")

      {:error, :expired} ->
        conn
        |> render(:code_entry,
          email: email,
          error: "Der Code ist abgelaufen. Bitte fordere einen neuen an."
        )

      {:error, :too_many_attempts} ->
        conn
        |> render(:code_entry,
          email: email,
          error: "Zu viele Fehlversuche. Bitte fordere einen neuen Code an."
        )

      {:error, :invalid} ->
        conn
        |> render(:code_entry, email: email, error: "Ungültiger Code. Bitte versuche es erneut.")
    end
  end

  def verify(conn, _params), do: redirect(conn, to: "/admin/login")

  def resend(conn, %{"email" => email}) do
    case Accounts.deliver_login_code(email) do
      {:ok, _code} ->
        conn
        |> render(:code_entry, email: email, error: nil, resent: true)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, %{message: "E-Mail-Adresse nicht gefunden.", duration: 5000})
        |> redirect(to: "/admin/login")
    end
  end

  def resend(conn, _params), do: redirect(conn, to: "/admin/login")

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Abgemeldet.")
    |> redirect(to: "/admin/login")
  end
end
