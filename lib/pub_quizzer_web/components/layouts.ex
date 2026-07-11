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

  attr :max_width, :string, default: "max-w-2xl", doc: "max width class for the content area"

  attr :main_class, :string,
    default: "px-4 py-4 sm:pt-8 sm:pb-10 sm:px-6 lg:px-8",
    doc: "classes for the main element"

  attr :hide_nav_actions, :boolean,
    default: false,
    doc: "hides the navbar action buttons (for quiz lobby screens)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope[:admin] do %>
      <header class="bg-base-200 border-b border-base-300 px-4 sm:px-6 py-2">
        <div class="flex items-center justify-between">
          <a href="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} width="28" />
            <span class="text-sm font-semibold">Pub Quizzer</span>
          </a>
          <div class="flex-none flex items-center gap-2">
            <.link navigate={~p"/join"} class="btn btn-ghost btn-sm">Quiz beitreten</.link>
            <.link navigate={~p"/admin/logout"} class="btn btn-ghost btn-sm">Abmelden</.link>
          </div>
        </div>
        <div class="flex items-center gap-1 mt-1">
          <.link navigate={~p"/admin/events"} class="btn btn-ghost btn-sm">Quizes</.link>
          <.link navigate={~p"/admin/topics"} class="btn btn-ghost btn-sm">Themen verwalten</.link>
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
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex-1 flex w-fit items-center gap-2">
            <img src={~p"/images/logo.svg"} width="36" />
            <span class="text-sm font-semibold">Pub Quizzer</span>
          </a>
        </div>
        <%= unless @hide_nav_actions do %>
          <div class="flex-none hidden sm:flex">
            <ul class="flex px-1 space-x-4 items-center">
              <li>
                <.link navigate={~p"/join"} class="btn btn-outline btn-sm">Quiz beitreten</.link>
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
              <button tabindex="0" class="btn btn-outline btn-sm text-lg leading-none">
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
