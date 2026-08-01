defmodule PubQuizzerWeb.Admin.UserLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope[:user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Bitte melde dich an.")
         |> redirect(to: "/admin/login")}

      user.role != "superadmin" ->
        {:ok,
         socket
         |> put_flash(:error, "Keine Berechtigung für diesen Bereich.")
         |> redirect(to: "/admin/events")}

      true ->
        users = Accounts.list_users()
        base_url = connect_base_url(socket)

        {:ok,
         socket
         |> assign(:users, users)
         |> assign(:page_title, "Benutzer")
         |> assign(:form, to_form(%{"email" => "", "name" => ""}))
         |> assign(:confirm_action, nil)
         |> assign(:pending_delete_id, nil)
         |> assign(:base_url, base_url)}
    end
  end

  @impl true
  def handle_event("invite", %{"email" => email, "name" => name}, socket) do
    current_user = socket.assigns.current_scope.user

    if Accounts.can_manage_users?(current_user) do
      case Accounts.create_user(%{email: email, name: name, role: "moderator"}) do
        {:ok, user} ->
          {:ok, raw_token} = Accounts.generate_invite_link(user)
          url = "#{socket.assigns.base_url}/admin/magic?token=#{raw_token}"

          {:noreply,
           socket
           |> assign(:users, Accounts.list_users())
           |> assign(:form, to_form(%{"email" => "", "name" => ""}))
           |> push_event("copy_to_clipboard", %{url: url})
           |> put_flash(:info, "Moderator hinzugefügt – Login-Link kopiert.")}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, "E-Mail-Adresse bereits registriert oder ungültig.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Keine Berechtigung.")}
    end
  end

  def handle_event("resend_link", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:ok, raw_token} = Accounts.generate_invite_link(user)
    url = "#{socket.assigns.base_url}/admin/magic?token=#{raw_token}"

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{url: url})
     |> put_flash(:info, "Login-Link für #{user.email} kopiert.")}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:confirm_action, :delete_user)
     |> assign(:pending_delete_id, String.to_integer(id))}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, socket |> assign(:confirm_action, nil) |> assign(:pending_delete_id, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    current_user = socket.assigns.current_scope.user
    id = socket.assigns.pending_delete_id

    cond do
      id == current_user.id ->
        {:noreply,
         socket
         |> assign(:confirm_action, nil)
         |> assign(:pending_delete_id, nil)
         |> put_flash(:error, "Du kannst dich nicht selbst löschen.")}

      Accounts.can_manage_users?(current_user) ->
        user = Accounts.get_user!(id)
        {:ok, _} = Accounts.delete_user(user)

        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:confirm_action, nil)
         |> assign(:pending_delete_id, nil)
         |> put_flash(:info, "Benutzer gelöscht.")}

      true ->
        {:noreply,
         socket
         |> assign(:confirm_action, nil)
         |> assign(:pending_delete_id, nil)
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

      <.form
        for={@form}
        id="add-user-form"
        phx-submit="invite"
        class="flex flex-col sm:flex-row gap-2 sm:items-center"
      >
        <input
          type="text"
          name="name"
          placeholder="Name"
          class="input input-sm w-full sm:flex-1"
          required
          autocomplete="name"
        />
        <input
          type="email"
          name="email"
          placeholder="name@beispiel.de"
          class="input input-sm w-full sm:flex-1"
          required
          autocomplete="email"
        />
        <button type="submit" class="btn btn-primary btn-sm shrink-0 w-full sm:w-44 gap-1.5">
          <.icon name="hero-plus" class="size-4" /> Hinzufügen
        </button>
      </.form>

      <div id="clipboard" phx-hook="ClipboardCopy" class="hidden" />

      <!-- User list -->
      <%!-- Mobile: cards --%>
      <div id="users-cards" class="space-y-3 lg:hidden">
        <div
          :for={user <- @users}
          id={"user-card-#{user.id}"}
          class="bg-base-200 border-2 border-base-300 rounded-xl px-4 pt-3 pb-3"
        >
          <div class="flex items-center justify-between gap-2 mb-1">
            <span class="text-sm font-medium">{if user.name && user.name != "",
              do: user.name,
              else: "—"}</span>
            <span class={[
              "badge badge-sm shrink-0",
              user.role == "superadmin" && "badge-primary"
            ]}>
              {if user.role == "superadmin", do: "Superadmin", else: "Moderator"}
            </span>
          </div>
          <div class="flex items-center justify-between gap-2">
            <span class="font-mono text-sm break-all">{user.email}</span>
            <span class={[
              "badge badge-sm shrink-0",
              user.active && "badge-success",
              !user.active && "badge-error"
            ]}>
              {if user.active, do: "Aktiv", else: "Inaktiv"}
            </span>
          </div>
          <div class="text-xs text-base-content/60 mt-1">
            <%= if user.last_signed_in_at do %>
              Zuletzt: {Calendar.strftime(user.last_signed_in_at, "%d.%m.%y %H:%M")}
            <% else %>
              Nie angemeldet
            <% end %>
          </div>
          <div class="flex items-center justify-end gap-2 mt-2 pt-2 border-t border-base-300">
            <%= if user.id != @current_scope.user.id do %>
              <button
                phx-click="resend_link"
                phx-value-id={user.id}
                class="btn btn-xs btn-soft"
                title="Neuen Login-Link senden"
              >
                Link
              </button>
              <button
                phx-click="ask_delete"
                phx-value-id={user.id}
                class="btn btn-xs btn-danger-soft"
              >
                Löschen
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Desktop: table --%>
      <div class="overflow-x-auto rounded-lg border-2 border-base-300 hidden lg:block">
        <table class="table table-sm">
          <thead>
            <tr class="border-b-2 border-base-300 bg-base-300">
              <th>Name</th>
              <th>E-Mail</th>
              <th>Rolle</th>
              <th>Status</th>
              <th>Letzte Anmeldung</th>
              <th class="text-right">Aktionen</th>
            </tr>
          </thead>
          <tbody id="users" class="divide-y divide-base-300">
            <tr :for={user <- @users} id={"user-#{user.id}"} class="bg-base-200 hover">
              <td class="font-medium">
                {if user.name && user.name != "", do: user.name, else: "—"}
              </td>
              <td class="font-mono text-sm">{user.email}</td>
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
                      class="btn btn-xs btn-soft"
                      title="Neuen Login-Link senden"
                    >
                      Link
                    </button>
                    <button
                      phx-click="ask_delete"
                      phx-value-id={user.id}
                      class="btn btn-xs btn-danger-soft"
                    >
                      Löschen
                    </button>
                  <% end %>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.confirm_modal
        id="delete-user-modal"
        show={@confirm_action == :delete_user}
        title="Benutzer löschen?"
        message="Diesen Benutzer unwiderruflich löschen?"
        confirm_label="Löschen"
        confirm_event="confirm_delete"
        cancel_event="cancel_confirm"
      />
    </Layouts.app>
    """
  end
end
