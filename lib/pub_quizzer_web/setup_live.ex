defmodule PubQuizzerWeb.SetupLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.has_users?() do
      {:ok, push_navigate(socket, to: ~p"/admin/login")}
    else
      base_url = connect_base_url(socket)

      {:ok,
       assign(socket,
         form: to_form(%{"email" => "", "name" => ""}),
         magic_link_url: nil,
         base_url: base_url
       )}
    end
  end

  @impl true
  def handle_event("save", %{"email" => email, "name" => name}, socket) do
    if Accounts.has_users?() do
      {:noreply, push_navigate(socket, to: ~p"/admin/login")}
    else
      case Accounts.create_user(%{email: email, name: name, role: "superadmin"}) do
        {:ok, user} ->
          {:ok, raw_token} = Accounts.generate_invite_link(user)
          url = "#{socket.assigns.base_url}/admin/magic?token=#{raw_token}"
          {:noreply, assign(socket, magic_link_url: url)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Ungültige E-Mail-Adresse.")
           |> assign(form: to_form(changeset))}
      end
    end
  end

  defp connect_base_url(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      nil -> PubQuizzerWeb.Endpoint.url()
      uri -> "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} max_width="max-w-full" main_class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-center min-h-[calc(100vh-4rem)]">
        <div class="text-center max-w-sm w-full">
          <%= if @magic_link_url do %>
            <.icon name="hero-check-circle" class="size-[4rem] mx-auto text-success" />
            <h1 class="text-3xl font-bold mt-4">Superadmin erstellt!</h1>
            <p class="py-4 text-base-content/70">
              Ein Login-Link wurde generiert. Klicke darauf, um dich anzumelden.
            </p>
            <div class="alert alert-info mt-4 text-left">
              <div class="text-sm break-all">
                <span class="font-semibold">Login-Link:</span><br />
                <a href={@magic_link_url} class="link link-primary">{@magic_link_url}</a>
              </div>
            </div>
            <div class="mt-4">
              <a href={@magic_link_url} class="btn btn-primary btn-block">Anmelden</a>
            </div>
          <% else %>
            <.icon name="hero-wrench-screwdriver" class="size-[4rem] mx-auto text-primary" />
            <h1 class="text-3xl font-bold mt-4">Ersteinrichtung</h1>
            <p class="py-4 text-base-content/70">
              Erstelle das erste Superadmin-Konto für Quiz for a better life.
            </p>
            <.form for={@form} id="setup-form" phx-submit="save">
              <.input
                field={@form[:name]}
                type="text"
                placeholder="Name"
                required
                autocomplete="name"
              />
              <.input
                field={@form[:email]}
                type="email"
                placeholder="name@beispiel.de"
                required
                autocomplete="email"
              />
              <button type="submit" class="btn btn-primary btn-block mt-4">
                Superadmin erstellen
              </button>
            </.form>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
