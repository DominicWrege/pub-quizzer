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
      <%!-- Below lg the document scrolls naturally so iOS Safari's floating URL
          bar collapses on scroll instead of permanently clipping the shell's
          bottom; lg+ keeps the viewport-locked shell with <main> as scroller. --%>
      <div
        class="flex min-h-[var(--app-height)] flex-col lg:h-[var(--app-height)] lg:overflow-hidden"
        data-app-shell
      >
        <input type="checkbox" id="nav-drawer-toggle" class="peer hidden" />
        <header
          class="sticky top-0 z-20 shrink-0 bg-base-200 border-b border-base-300 pl-[calc(env(safe-area-inset-left)+1rem)] pr-[calc(env(safe-area-inset-right)+1rem)] sm:pl-[calc(env(safe-area-inset-left)+1.5rem)] sm:pr-[calc(env(safe-area-inset-right)+1.5rem)] pt-[calc(env(safe-area-inset-top)+0.5rem)] pb-0"
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
                <.icon name="hero-bars-3" class="size-6" />
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
          class="fixed inset-x-0 top-0 z-40 h-[var(--app-height)] bg-black/50 opacity-0 invisible pointer-events-none peer-checked:opacity-100 peer-checked:visible peer-checked:pointer-events-auto transition-[opacity,visibility] duration-200 sm:hidden"
        ></label>
        <div class="flex min-h-0 flex-1">
          <main class={["flex-1 lg:overflow-y-auto lg:overscroll-contain", @main_class]}>
            <%!-- Top padding lives here (not on <main>) so sticky toolbars pin
              flush with the header instead of being inset by main's padding. --%>
            <div class={[
              "mx-auto space-y-2 sm:space-y-6 max-w-full sm:max-w-none pt-2 sm:pt-4 pb-[env(safe-area-inset-bottom)]",
              @max_width
            ]}>
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
        <%!-- shadow only while open: a shadow on the translated-off-screen drawer
            bleeds into the top of the viewport when closed --%>
        <aside class="fixed inset-x-0 top-0 z-50 max-h-[var(--app-height)] overflow-y-auto bg-base-100 border-b border-base-300 -translate-y-full peer-checked:translate-y-0 peer-checked:shadow-xl transition-[transform,box-shadow] duration-200 sm:hidden flex flex-col">
          <div class="flex items-center justify-between px-4 pt-[calc(env(safe-area-inset-top)+1rem)] pb-4 border-b border-base-300">
            <span class="font-semibold">Navigation</span>
            <label
              for="nav-drawer-toggle"
              class="btn btn-ghost btn-sm btn-square"
              aria-label="Schließen"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </label>
          </div>
          <nav class="menu menu-md p-4 gap-1">
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
          <div class="px-4 pt-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] border-t border-base-300">
            <.link navigate={~p"/admin/logout"} class="btn btn-soft btn-sm w-full justify-start gap-2">
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Abmelden
            </.link>
          </div>
        </aside>
      </div>
    <% else %>
      <%!-- Flex column fills the viewport so <main> (and any bg it carries,
          e.g. the login page) always reaches the bottom edge. min-h-0 on the
          navbar: daisyUI's .navbar min-height (4rem) leaves dead bottom space
          vs the logged-in header; explicit top padding replaces the space the
          min-height used to provide. --%>
      <div class="flex min-h-svh flex-col">
        <header class="navbar min-h-0 pl-[calc(env(safe-area-inset-left)+1rem)] pr-[calc(env(safe-area-inset-right)+1rem)] sm:pl-[calc(env(safe-area-inset-left)+1.5rem)] sm:pr-[calc(env(safe-area-inset-right)+1.5rem)] lg:pl-[calc(env(safe-area-inset-left)+2rem)] lg:pr-[calc(env(safe-area-inset-right)+2rem)] pt-[calc(env(safe-area-inset-top)+0.5rem)] pb-2 border-b border-base-300">
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
                <button tabindex="0" class="btn btn-sm btn-square" aria-label="Menü">
                  <.icon name="hero-bars-3" class="size-6" />
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
        <main class={["flex-1", @main_class]}>
          <div class={["mx-auto space-y-4 pb-[env(safe-area-inset-bottom)]", @max_width]}>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
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
