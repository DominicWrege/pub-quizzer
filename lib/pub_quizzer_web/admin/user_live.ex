defmodule PubQuizzerWeb.Admin.UserLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Accounts

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    base_url = connect_base_url(socket)

    {:ok,
     socket
     |> assign(:users, users)
     |> assign(:page_title, "Benutzer")
     |> assign(:form, to_form(%{"email" => ""}))
     |> assign(:invite_link, nil)
     |> assign(:confirm_delete_id, nil)
     |> assign(:base_url, base_url)}
  end

  @impl true
  def handle_event("invite", %{"email" => email, "name" => name}, socket) do
    current_user = socket.assigns.current_scope.user

    if Accounts.can_manage_users?(current_user) do
      case Accounts.create_user(%{email: email, name: name, role: "moderator"}) do
        {:ok, user} ->
          {:ok, url} = Accounts.deliver_invite_link(user, socket.assigns.base_url)

          {:noreply,
           socket
           |> assign(:users, Accounts.list_users())
           |> assign(:form, to_form(%{"email" => ""}))
           |> assign(:invite_link, url)
           |> put_flash(:info, "Moderator hinzugefügt.")}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, "E-Mail-Adresse bereits registriert oder ungültig.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Keine Berechtigung.")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    current_user = socket.assigns.current_scope.user
    user = Accounts.get_user!(id)

    if Accounts.can_manage_users?(current_user) do
      if user.id == current_user.id do
        {:noreply, put_flash(socket, :error, "Du kannst dich nicht selbst deaktivieren.")}
      else
        {:ok, _} = Accounts.toggle_active(user)
        {:noreply, assign(socket, :users, Accounts.list_users())}
      end
    else
      {:noreply, put_flash(socket, :error, "Keine Berechtigung.")}
    end
  end

  def handle_event("resend_link", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:ok, url} = Accounts.deliver_invite_link(user, socket.assigns.base_url)

    {:noreply,
     socket
     |> assign(:invite_link, url)
     |> put_flash(:info, "Neuer Login-Link für #{user.email} generiert.")}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_id, String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_id, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    current_user = socket.assigns.current_scope.user
    id = socket.assigns.confirm_delete_id

    cond do
      id == current_user.id ->
        {:noreply,
         socket
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:error, "Du kannst dich nicht selbst löschen.")}

      Accounts.can_manage_users?(current_user) ->
        user = Accounts.get_user!(id)
        {:ok, _} = Accounts.delete_user(user)

        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:confirm_delete_id, nil)
         |> assign(:invite_link, nil)
         |> put_flash(:info, "Benutzer gelöscht.")}

      true ->
        {:noreply,
         socket
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:error, "Keine Berechtigung.")}
    end
  end

  defp connect_base_url(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      nil -> "http://localhost:4000"
      uri -> "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      max_width="max-w-4xl"
    >
      <.header>
        Benutzer
        <:subtitle>Moderatoren verwalten und Login-Links generieren.</:subtitle>
      </.header>

      <.form for={@form} id="add-user-form" phx-submit="invite" class="flex gap-2 items-center">
        <input
          type="email"
          name="email"
          placeholder="name@beispiel.de"
          class="input input-sm flex-1"
          required
          autocomplete="email"
        />
        <input
          type="text"
          name="name"
          placeholder="Name (optional)"
          class="input input-sm w-40"
          autocomplete="name"
        />
        <button type="submit" class="btn btn-primary btn-sm shrink-0">
          <.icon name="hero-plus" class="size-4" /> Hinzufügen
        </button>
      </.form>

      <%= if @invite_link do %>
        <div class="alert alert-info">
          <div class="text-sm break-all">
            <span class="font-semibold">Login-Link:</span><br />
            <a href={@invite_link} class="link link-primary">{@invite_link}</a>
          </div>
        </div>
      <% end %>

      <!-- User list -->
      <div class="overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>E-Mail</th>
              <th>Name</th>
              <th>Rolle</th>
              <th>Status</th>
              <th>Letzte Anmeldung</th>
              <th class="text-right">Aktionen</th>
            </tr>
          </thead>
          <tbody id="users">
            <tr :for={user <- @users} id={"user-#{user.id}"} class="hover">
              <td class="font-mono text-sm">{user.email}</td>
              <td class="font-medium">
                {if user.name && user.name != "", do: user.name, else: "—"}
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  user.role == "superadmin" && "badge-primary"
                ]}>
                  {if user.role == "superadmin", do: "Superadmin", else: "Moderator"}
                </span>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  user.active && "badge-success",
                  !user.active && "badge-error"
                ]}>
                  {if user.active, do: "Aktiv", else: "Inaktiv"}
                </span>
              </td>
              <td class="text-sm text-base-content/60">
                <%= if user.last_signed_in_at do %>
                  {Calendar.strftime(user.last_signed_in_at, "%d.%m.%y %H:%M")}
                <% else %>
                  —
                <% end %>
              </td>
              <td class="text-right">
                <div class="flex gap-1 justify-end">
                  <%= if user.id != @current_scope.user.id do %>
                    <button
                      phx-click="resend_link"
                      phx-value-id={user.id}
                      class="btn btn-ghost btn-xs"
                      title="Neuen Login-Link senden"
                    >
                      Link
                    </button>
                    <button
                      phx-click="toggle_active"
                      phx-value-id={user.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {if user.active, do: "Deaktivieren", else: "Aktivieren"}
                    </button>
                    <%= if @confirm_delete_id == user.id do %>
                      <button phx-click="confirm_delete" class="btn btn-error btn-xs">
                        Wirklich?
                      </button>
                      <button phx-click="cancel_delete" class="btn btn-ghost btn-xs">
                        Abbrechen
                      </button>
                    <% else %>
                      <button
                        phx-click="ask_delete"
                        phx-value-id={user.id}
                        class="btn btn-ghost btn-xs text-error"
                      >
                        Löschen
                      </button>
                    <% end %>
                  <% end %>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
