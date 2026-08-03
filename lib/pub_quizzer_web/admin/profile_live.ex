defmodule PubQuizzerWeb.Admin.ProfileLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.role != "superadmin" do
      {:ok,
       socket
       |> put_flash(:error, "Keine Berechtigung für diesen Bereich.")
       |> redirect(to: "/admin/events")}
    else
      form = to_form(Accounts.change_user(user))
      {:ok, assign(socket, page_title: "Profil", form: form)}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user(user, user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:form, to_form(Accounts.change_user(updated_user)))
         |> assign(:current_scope, %{user: updated_user})
         |> put_flash(:info, "Name gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      max_width="max-w-md"
    >
      <.header>
        Profil
        <:subtitle>Deinen Namen bearbeiten</:subtitle>
      </.header>

      <.form for={@form} id="profile-form" phx-submit="save" class="space-y-4">
        <.input field={@form[:email]} type="email" label="E-Mail" disabled />
        <.input field={@form[:name]} type="text" label="Name" placeholder="Dein Name" />
        <button type="submit" class="btn btn-primary">Speichern</button>
      </.form>
    </Layouts.app>
    """
  end
end
