defmodule PubQuizzerWeb.SetupLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.has_users?() do
      {:ok, push_navigate(socket, to: ~p"/admin/login")}
    else
      {:ok,
       assign(socket,
         form: to_form(%{"email" => "", "name" => ""}),
         login_code: nil
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
          {:ok, code} = Accounts.generate_login_code_for(user)
          {:noreply, assign(socket, login_code: code)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Ungültige E-Mail-Adresse.")
           |> assign(form: to_form(changeset))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} max_width="max-w-full" main_class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-center min-h-[calc(100vh-8rem)]">
        <div class="text-center max-w-sm w-full">
          <%= if @login_code do %>
            <.icon name="hero-check-circle" class="size-[4rem] mx-auto text-success" />
            <h1 class="text-3xl font-bold mt-4">Superadmin erstellt!</h1>
            <p class="py-4 text-base-content/70">
              Dein Login-Code lautet:
            </p>
            <div
              id="setup-login-code"
              class="font-mono text-3xl font-bold tracking-[0.3em] text-primary bg-base-200 rounded-lg py-4 mb-2"
            >
              {@login_code}
            </div>
            <p class="text-sm text-base-content/60">
              Der Code ist 10 Minuten gültig. Gib ihn auf der Login-Seite ein.
            </p>
            <div class="mt-4">
              <.link navigate={~p"/admin/login"} class="btn btn-primary btn-block">
                Zum Login
              </.link>
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
