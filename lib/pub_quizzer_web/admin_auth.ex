defmodule PubQuizzerWeb.AdminAuth do
  @moduledoc """
  Plug-based admin authentication via a signed session cookie.

  Reads `:admin` from the session. Redirects to /admin/login if absent.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :admin) == true do
      conn |> assign(:current_scope, %{admin: true})
    else
      conn
      |> put_flash(:error, "Please sign in to access the admin panel.")
      |> redirect(to: "/admin/login")
      |> halt()
    end
  end

  def on_mount(:mount_current_scope, _params, session, socket) do
    if session["admin"] == true do
      socket =
        socket
        |> Phoenix.Component.assign(:current_scope, %{admin: true})
        |> Phoenix.LiveView.attach_hook(:set_current_path, :handle_params, fn _params,
                                                                              url,
                                                                              socket ->
          {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(url).path)}
        end)

      {:cont, socket}
    else
      {:cont, socket}
    end
  end
end
