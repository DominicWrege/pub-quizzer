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
    default: "px-4 pb-4 sm:pb-10 sm:px-6 lg:px-8",
    doc: "classes for the main element"

  attr :hide_nav_actions, :boolean,
    default: false,
    doc: "hides the navbar action buttons (for quiz lobby screens)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope[:user] do %>
      <div class="flex h-dvh flex-col overflow-hidden" data-app-shell>
        <input type="checkbox" id="nav-drawer-toggle" class="peer hidden" />
        <header
          class="shrink-0 bg-base-200 border-b border-base-300 px-4 sm:px-6 pt-2 pb-0"
          data-guide-seen={"#{@current_scope.user.guide_seen}"}
          data-guide-role={@current_scope.user.role}
        >
          <div class="flex items-center justify-between mb-1.5">
            <div class="flex items-center gap-2 min-w-0">
              <label
                for="nav-drawer-toggle"
                class="btn btn-sm btn-soft btn-square sm:hidden shrink-0"
                aria-label="Menü"
              >
                <span class="text-lg leading-none">&#9776;</span>
              </label>
              <a href="/" class="flex items-center gap-2 min-w-0">
                <span class="text-sm sm:text-xl font-semibold truncate">Quiz for a better life</span>
              </a>
            </div>
            <div class="flex-none flex items-center gap-4">
              <details
                class="dropdown dropdown-end"
                phx-click-away={Phoenix.LiveView.JS.remove_attribute("open")}
              >
                <summary class="btn btn-sm btn-soft rounded-full p-0 w-8 h-8">
                  <div class="avatar avatar-placeholder">
                    <div class="bg-primary text-primary-content rounded-full w-7 text-xs font-semibold flex items-center justify-center">
                      {String.at(@current_scope.user.name || "?", 0)}
                    </div>
                  </div>
                </summary>
                <ul class="dropdown-content menu bg-base-100 rounded-box shadow-lg min-w-40 p-2 mt-2 z-50 border border-base-200">
                  <%= if @current_scope.user.role == "superadmin" do %>
                    <li>
                      <.link navigate={~p"/admin/profile"} class="text-sm">
                        <span class="truncate max-w-32">{@current_scope.user.name || "Profil"}</span>
                      </.link>
                    </li>
                  <% end %>
                  <li>
                    <.link navigate={~p"/admin/logout"} class="text-sm">
                      <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Abmelden
                    </.link>
                  </li>
                </ul>
              </details>
            </div>
          </div>
          <div class="hidden sm:flex items-center gap-1 overflow-x-auto">
            <.link
              navigate={~p"/admin/events"}
              class={nav_tab_class(@current_path, "/admin/events")}
            >
              <.icon name="hero-play" class="size-4 hidden sm:inline" /> Quiz
            </.link>
            <.link
              navigate={~p"/admin/topics"}
              class={nav_tab_class(@current_path, "/admin/topics")}
            >
              <.icon name="hero-bookmark" class="size-4 hidden sm:inline" /> Themen verwalten
            </.link>
            <%= if @current_scope.user.role == "superadmin" do %>
              <.link
                navigate={~p"/admin/users"}
                class={nav_tab_class(@current_path, "/admin/users")}
              >
                <.icon name="hero-key" class="size-4 hidden sm:inline" /> Benutzer
              </.link>
            <% end %>
          </div>
        </header>
        <label
          for="nav-drawer-toggle"
          aria-hidden="true"
          class="fixed inset-0 z-40 bg-black/50 opacity-0 pointer-events-none peer-checked:opacity-100 peer-checked:pointer-events-auto transition-opacity duration-200 sm:hidden"
        ></label>
        <div class="flex min-h-0 flex-1">
          <main class={["flex-1 overflow-y-auto overscroll-contain", @main_class]}>
            <%!-- Top padding lives here (not on <main>) so sticky toolbars pin
              flush with the header instead of being inset by main's padding. --%>
            <div class={[
              "mx-auto space-y-3 sm:space-y-6 max-w-full sm:max-w-none pt-2 sm:pt-4",
              @max_width
            ]}>
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
        <aside class="fixed top-0 left-0 z-50 h-dvh w-72 max-w-[80vw] bg-base-100 border-r border-base-300 shadow-xl -translate-x-full peer-checked:translate-x-0 transition-transform duration-200 sm:hidden flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <span class="font-semibold">Navigation</span>
            <label
              for="nav-drawer-toggle"
              class="btn btn-ghost btn-sm btn-square"
              aria-label="Schließen"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </label>
          </div>
          <nav class="menu menu-md p-4 gap-1 flex-1">
            <.link
              navigate={~p"/admin/events"}
              class={drawer_link_class(@current_path, "/admin/events")}
            >
              <.icon name="hero-play" class="size-4" /> Quiz
            </.link>
            <.link
              navigate={~p"/admin/topics"}
              class={drawer_link_class(@current_path, "/admin/topics")}
            >
              <.icon name="hero-bookmark" class="size-4" /> Themen verwalten
            </.link>
            <%= if @current_scope.user.role == "superadmin" do %>
              <.link
                navigate={~p"/admin/users"}
                class={drawer_link_class(@current_path, "/admin/users")}
              >
                <.icon name="hero-key" class="size-4" /> Benutzer
              </.link>
            <% end %>
          </nav>
          <div class="p-4 border-t border-base-300">
            <.link navigate={~p"/admin/logout"} class="btn btn-soft btn-sm w-full justify-start gap-2">
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Abmelden
            </.link>
          </div>
        </aside>
      </div>
    <% else %>
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <a href="/" class="flex-1 flex w-fit items-center gap-2">
            <span class="text-sm sm:text-xl font-semibold">Quiz for a better life</span>
          </a>
        </div>
        <%= unless @hide_nav_actions do %>
          <div class="flex-none hidden sm:flex">
            <ul class="flex px-1 space-x-4 items-center">
              <%= if @current_scope && @current_scope[:user] do %>
                <li>
                  <.link navigate={~p"/admin/events"} class="btn btn-primary btn-sm">
                    Verwaltung <span aria-hidden="true">&rarr;</span>
                  </.link>
                </li>
              <% else %>
                <li>
                  <.link navigate={~p"/admin/login"} class="btn btn-soft btn-sm">Moderator</.link>
                </li>
              <% end %>
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
                <%= if @current_scope && @current_scope[:user] do %>
                  <li>
                    <.link navigate={~p"/admin/events"}>Verwaltung &rarr;</.link>
                  </li>
                <% else %>
                  <li>
                    <.link navigate={~p"/admin/login"}>Moderator</.link>
                  </li>
                <% end %>
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
      "inline-flex items-center gap-1 sm:gap-2 px-2 sm:px-4 py-2 text-sm border-b-2 transition-colors duration-150"

    active_styles =
      "border-primary text-base-content font-semibold border-b-[3px]"

    inactive_styles =
      "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/20"

    if active, do: [base, active_styles], else: [base, inactive_styles]
  end

  defp drawer_link_class(current_path, prefix) do
    active = String.starts_with?(current_path, prefix)

    base = "flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-colors"

    if active do
      [base, "bg-primary text-primary-content font-semibold"]
    else
      [base, "text-base-content hover:bg-base-200"]
    end
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
