defmodule PubQuizzerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PubQuizzerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_path, :string,
    default: "",
    doc: "the current request path (for active nav highlighting)"

  attr :max_width, :string, default: "max-w-2xl", doc: "max width class for the content area"

  attr :main_class, :string,
    default: "px-4 pt-2 sm:pt-4 pb-4 sm:pb-10 sm:px-6 lg:px-8",
    doc: "classes for the main element"

  attr :hide_nav_actions, :boolean,
    default: false,
    doc: "hides the navbar action buttons (for quiz lobby screens)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope[:user] do %>
      <header class="bg-base-200 border-b border-base-300 px-4 sm:px-6 pt-2 pb-0">
        <div class="flex items-center justify-between mb-1.5">
          <a href="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} width="28" />
            <span class="text-sm sm:text-xl font-semibold">Quiz for a better life</span>
          </a>
          <div class="flex-none flex items-center gap-4">
            <details class="dropdown dropdown-end">
              <summary class="btn btn-sm btn-soft rounded-full p-0 w-8 h-8">
                <div class="avatar avatar-placeholder">
                  <div class="bg-primary text-primary-content rounded-full w-7 text-xs font-semibold flex items-center justify-center">
                    {String.at(@current_scope.user.name || "?", 0)}
                  </div>
                </div>
              </summary>
              <ul class="dropdown-content menu bg-base-100 rounded-box shadow-lg min-w-40 p-2 mt-2 z-50 border border-base-200">
                <li>
                  <.link navigate={~p"/admin/profile"} class="text-sm">
                    <span class="truncate max-w-32">{@current_scope.user.name || "Profil"}</span>
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/admin/logout"} class="text-sm">
                    <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Abmelden
                  </.link>
                </li>
              </ul>
            </details>
          </div>
        </div>
        <div class="flex items-center gap-1">
          <.link
            navigate={~p"/admin/events"}
            class={nav_tab_class(@current_path, "/admin/events")}
          >
            <.icon name="hero-play" class="size-4" /> Quiz
          </.link>
          <.link
            navigate={~p"/admin/topics"}
            class={nav_tab_class(@current_path, "/admin/topics")}
          >
            <.icon name="hero-bookmark" class="size-4" /> Themen verwalten
          </.link>
          <%= if @current_scope.user.role == "superadmin" do %>
            <.link
              navigate={~p"/admin/users"}
              class={nav_tab_class(@current_path, "/admin/users")}
            >
              <.icon name="hero-key" class="size-4" /> Benutzer
            </.link>
          <% end %>
        </div>
      </header>
      <div class="flex">
        <main class={["flex-1", @main_class]}>
          <div class={["mx-auto space-y-6 max-w-full sm:max-w-none", @max_width]}>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    <% else %>
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <a href="/" class="flex-1 flex w-fit items-center gap-2">
            <img src={~p"/images/logo.svg"} width="36" />
            <span class="text-sm sm:text-xl font-semibold">Quiz for a better life</span>
          </a>
        </div>
        <%= unless @hide_nav_actions do %>
          <div class="flex-none hidden sm:flex">
            <ul class="flex px-1 space-x-4 items-center">
              <li>
                <.link navigate={~p"/join"} class="btn btn-sm btn-soft">Quiz beitreten</.link>
              </li>
              <li>
                <.link navigate={~p"/admin/login"} class="btn btn-primary btn-sm">
                  Verwaltung <span aria-hidden="true">&rarr;</span>
                </.link>
              </li>
            </ul>
          </div>
          <div class="flex-none sm:hidden">
            <div class="dropdown dropdown-end">
              <button tabindex="0" class="btn btn-sm text-lg leading-none">
                &#9776;
              </button>
              <ul
                tabindex="0"
                class="dropdown-content menu bg-base-200 rounded-box w-52 shadow-lg z-50 mt-2"
              >
                <li>
                  <.link navigate={~p"/join"} class="font-semibold">Quiz beitreten</.link>
                </li>
                <li>
                  <.link navigate={~p"/admin/login"}>Verwaltung &rarr;</.link>
                </li>
              </ul>
            </div>
          </div>
        <% end %>
      </header>
      <main class={@main_class}>
        <div class={["mx-auto space-y-4", @max_width]}>
          {render_slot(@inner_block)}
        </div>
      </main>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  defp nav_tab_class(current_path, prefix) do
    active = String.starts_with?(current_path, prefix)

    base =
      "inline-flex items-center gap-2 px-4 py-2 text-sm border-b-2 transition-colors duration-150"

    active_styles =
      "border-primary text-base-content font-semibold border-b-[3px]"

    inactive_styles =
      "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/20"

    if active, do: [base, active_styles], else: [base, inactive_styles]
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
