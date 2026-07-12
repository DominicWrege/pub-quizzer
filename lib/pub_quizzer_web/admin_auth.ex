defmodule PubQuizzerWeb.AdminAuth do
  @moduledoc """
  Plug-based authentication via magic link sessions.

  Reads `:user_id` from the session, loads the user, and sets `current_scope`.
  Supports two levels: `:moderator_auth` (any active user) and
  `:superadmin_auth` (only superadmin role).
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias PubQuizzer.Accounts
  alias PubQuizzer.Accounts.User

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    required_role = Keyword.get(opts, :required_role, :moderator)

    case load_current_user(conn) do
      {:ok, user} ->
        if role_authorized?(user, required_role) do
          assign(conn, :current_scope, %{user: user})
        else
          conn
          |> put_flash(:error, "Keine Berechtigung für diesen Bereich.")
          |> redirect(to: "/admin/events")
          |> halt()
        end

      :error ->
        conn
        |> put_flash(:error, "Bitte melde dich an, um auf den Verwaltungsbereich zuzugreifen.")
        |> redirect(to: "/admin/login")
        |> halt()
    end
  end

  defp load_current_user(conn) do
    case get_session(conn, :user_id) do
      nil ->
        :error

      user_id ->
        case Accounts.get_user(user_id) do
          %User{active: true} = user -> {:ok, user}
          %User{active: false} -> :error
          nil -> :error
        end
    end
  end

  defp role_authorized?(_user, :moderator), do: true
  defp role_authorized?(%User{role: "superadmin"}, :superadmin), do: true
  defp role_authorized?(_, :superadmin), do: false

  def on_mount(:mount_current_scope, _params, session, socket) do
    socket =
      case load_current_user_from_session(session) do
        {:ok, user} ->
          socket
          |> Phoenix.Component.assign(:current_scope, %{user: user})

        :error ->
          socket
      end

    socket =
      socket
      |> Phoenix.LiveView.attach_hook(:set_current_path, :handle_params, fn _params,
                                                                            url,
                                                                            socket ->
        {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
      end)

    {:cont, socket}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case load_current_user_from_session(session) do
      {:ok, user} ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_scope, %{user: user})
          |> Phoenix.LiveView.attach_hook(:set_current_path, :handle_params, fn _params,
                                                                                url,
                                                                                socket ->
            {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
          end)

        {:cont, socket}

      :error ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Bitte melde dich an.")
         |> Phoenix.LiveView.redirect(to: "/admin/login")}
    end
  end

  def on_mount(:ensure_superadmin, _params, session, socket) do
    case load_current_user_from_session(session) do
      {:ok, %User{role: "superadmin"} = user} ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_scope, %{user: user})
          |> Phoenix.LiveView.attach_hook(:set_current_path, :handle_params, fn _params,
                                                                                url,
                                                                                socket ->
            {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
          end)

        {:cont, socket}

      {:ok, _user} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Keine Berechtigung für diesen Bereich.")
         |> Phoenix.LiveView.redirect(to: "/admin/events")}

      :error ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Bitte melde dich an.")
         |> Phoenix.LiveView.redirect(to: "/admin/login")}
    end
  end

  defp load_current_user_from_session(session) do
    case session["user_id"] do
      nil ->
        :error

      user_id ->
        case Accounts.get_user(user_id) do
          %User{active: true} = user -> {:ok, user}
          _ -> :error
        end
    end
  end
end
