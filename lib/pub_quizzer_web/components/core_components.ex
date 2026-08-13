defmodule PubQuizzerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={flash_raw = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      data-flash
      phx-hook="AutoDismiss"
      phx-mounted={
        JS.show(
          to: :this,
          time: 300,
          transition:
            {"transition-all ease-out duration-300",
             "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
             "opacity-100 translate-y-0 sm:scale-100"}
        )
      }
      data-duration={extract_duration(flash_raw)}
      role="alert"
      class="toast toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-[calc(100vw-2rem)] sm:w-96 max-w-[calc(100vw-2rem)] sm:max-w-96 text-wrap shadow-lg",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{extract_msg(flash_raw)}</p>
        </div>
        <button
          type="button"
          class="btn btn-sm btn-ghost px-1 text-white"
          aria-label="close"
          phx-click={JS.hide(to: "##{@id}")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  defp extract_msg(%{message: msg}), do: msg
  defp extract_msg(msg), do: msg

  defp extract_duration(%{duration: d}), do: d
  defp extract_duration(_), do: nil

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.

  By default the actions stack below the title on small screens. Pass
  `inline_actions` to keep them on the title row instead, which suits headers
  with a single compact action such as a save button.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions
  slot :back, doc: "renders a back button on the left side"

  attr :inline_actions, :boolean,
    default: false,
    doc: "keep the actions on the title row on small screens instead of stacking them below"

  attr :class, :any, default: nil, doc: "extra classes merged onto the outer header element"

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] &&
        if(@inline_actions,
          do: "flex flex-wrap items-start gap-x-2 gap-y-2 sm:gap-x-4",
          else:
            "flex flex-col lg:flex-row items-stretch lg:items-center justify-between gap-3 lg:gap-6"
        ),
      "pb-2",
      @class
    ]}>
      <div class={[
        "flex",
        if(@inline_actions,
          do: "items-start gap-2 sm:gap-4 min-w-0 flex-1",
          else: "items-center gap-4"
        )
      ]}>
        <div :if={@back != []} class="flex-none">
          {render_slot(@back)}
        </div>
        <div class={
          if(@inline_actions,
            do: "flex flex-col min-w-0 flex-1",
            else: "flex items-baseline gap-2 flex-wrap"
          )
        }>
          <h1 class={["text-lg font-semibold leading-8", @inline_actions && "truncate min-w-0"]}>
            {render_slot(@inner_block)}
          </h1>
          <p :if={@subtitle != []} class="text-sm text-base-content/70">
            {render_slot(@subtitle)}
          </p>
        </div>
      </div>
      <div class={[
        "flex flex-wrap items-center justify-end gap-2 sm:gap-3",
        if(@inline_actions, do: "ml-auto flex-none", else: "w-full lg:w-auto")
      ]}>
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Consistent back-navigation button: icon-only on mobile, icon + label from
  `sm:` up. Use for every admin back link so they never drift apart in style.
  """
  attr :navigate, :string, required: true
  attr :label, :string, default: "Zurück"

  def back_link(assigns) do
    ~H"""
    <.link navigate={@navigate} aria-label={@label} class="btn btn-xs sm:btn-sm btn-soft gap-1">
      <.icon name="hero-arrow-left" class="size-4" />
      <span class="hidden sm:inline">{@label}</span>
    </.link>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  attr :class, :string,
    default: "",
    doc: "additional CSS classes for the table element"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto rounded-lg border-2 border-base-300">
      <table class={["table", @class]}>
        <thead>
          <tr class="bg-base-300 border-b-2 border-base-300">
            <th :for={col <- @col}>{col[:label]}</th>
            <th :if={@action != []}>
              <span class="sr-only">Aktionen</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-base-300"
        >
          <tr
            :for={row <- @rows}
            class="bg-base-200"
            id={@row_id && @row_id.(row)}
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={@row_click && "hover:cursor-pointer"}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 font-semibold">
              <div class="flex gap-4">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> name} = assigns) do
    svg_content = icon_svg(name)
    assigns = assign(assigns, :svg_content, svg_content)

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      class={@class}
    >
      {Phoenix.HTML.raw(@svg_content)}
    </svg>
    """
  end

  @doc """
  Renders user-authored text while preserving its line breaks as `<br>` tags.

  Unlike applying `whitespace-pre-wrap`/`pre-line` to a container, this does
  not leak the surrounding template's own indentation or newlines, because the
  parent element keeps normal whitespace handling. When the parent is a flex
  container (such as daisyUI's `card-title`), wrap the component in a single
  inline element so its lines stay stacked.
  """
  attr :text, :string, default: nil

  def multiline_text(assigns) do
    ~H"""
    <%= for {line, index} <- Enum.with_index(String.split(@text || "", "\n")) do %>
      <%= if index > 0 do %>
        <br />
      <% end %>
      {line}
    <% end %>
    """
  end

  defp icon_svg(name) do
    case name do
      "list-bullet" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0ZM3.75 12h.007v.008H3.75V12Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm-.375 5.25h.007v.008H3.75v-.008Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z"/>)

      "x-mark" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12"/>)

      "magnifying-glass" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"/>)

      "chevron-right" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5"/>)

      "chevron-left" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m15.75 19.5-7.5-7.5 7.5-7.5"/>)

      "eye" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"/>)

      "flag" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M3 3v1.5M3 21v-6m0 0 2.77-.693a9 9 0 0 1 6.208.682l.108.054a9 9 0 0 0 6.086.71l3.114-.732a48.524 48.524 0 0 1-.005-10.499l-3.11.732a9 9 0 0 1-6.085-.711l-.108-.054a9 9 0 0 0-6.208-.682L3 4.5M3 15V4.5"/>)

      "exclamation-circle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z"/>)

      "arrow-path" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182"/>)

      "trash" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"/>)

      "plus" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/>)

      "minus" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M5 12h14"/>)

      "information-circle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"/>)

      "clock" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>)

      "trophy" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 18.75h-9m9 0a3 3 0 0 1 3 3h-15a3 3 0 0 1 3-3m9 0v-3.375c0-.621-.503-1.125-1.125-1.125h-.871M7.5 18.75v-3.375c0-.621.504-1.125 1.125-1.125h.872m5.007 0H9.497m5.007 0a7.454 7.454 0 0 1-.982-3.172M9.497 14.25a7.454 7.454 0 0 0 .981-3.172M5.25 4.236c-.982.143-1.954.317-2.916.52A6.003 6.003 0 0 0 7.73 9.728M5.25 4.236V4.5c0 2.108.966 3.99 2.48 5.228M5.25 4.236V2.721C7.456 2.41 9.71 2.25 12 2.25c2.291 0 4.545.16 6.75.47v1.516M18.75 4.236c.982.143 1.954.317 2.916.52A6.003 6.003 0 0 1 16.27 9.728M18.75 4.236V4.5c0 2.108-.966 3.99-2.48 5.228m0 0a6.023 6.023 0 0 1-2.77.72 6.023 6.023 0 0 1-2.77-.72m0 0-.007-.008Z"/>)

      "bookmark" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0 1 11.186 0Z"/>)

      "sparkles" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 0 0-2.455 2.456ZM16.894 20.567 16.5 21.75l-.394-1.183a2.25 2.25 0 0 0-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 0 0 1.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 0 0 1.423 1.423l1.183.394-1.183.394a2.25 2.25 0 0 0-1.423 1.423Z"/>)

      "check-circle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>)

      "x-circle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>)

      "hand-raised" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M10.05 4.575a1.575 1.575 0 1 0-3.15 0v3m3.15-3v-1.5a1.575 1.575 0 0 1 3.15 0v1.5m-3.15 0 .075 5.925m3.075.75V4.575m0 0a1.575 1.575 0 0 1 3.15 0V15M6.9 7.575a1.575 1.575 0 1 0-3.15 0v8.175a6.75 6.75 0 0 0 6.75 6.75h2.018a5.25 5.25 0 0 0 3.712-1.538l1.732-1.732a5.25 5.25 0 0 0 1.538-3.712l.003-2.024a.668.668 0 0 1 .198-.471 1.575 1.575 0 1 0-2.228-2.228 3.818 3.818 0 0 0-1.12 2.687M6.9 7.575V12m6.27 4.318A4.49 4.49 0 0 1 16.35 15m.002 0h-.002"/>)

      "star" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z"/>)

      "exclamation-triangle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"/>)

      "key" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25a3 3 0 0 1 3 3m3 0a6 6 0 0 1-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1 1 21.75 8.25Z"/>)

      "lock-closed" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"/>)

      "play" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.347a1.125 1.125 0 0 1 0 1.972l-11.54 6.347a1.125 1.125 0 0 1-1.667-.986V5.653Z"/>)

      "pencil" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10"/>)

      "clipboard" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9a.75.75 0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 0 1 1.927-.184"/>)

      "calendar" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5"/>)

      "arrow-right-on-rectangle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9"/>)

      "envelope" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75"/>)

      "wrench-screwdriver" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17 17.25 21A2.652 2.652 0 0 0 21 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 1 1-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 0 0 4.486-6.336l-3.276 3.277a3.004 3.004 0 0 1-2.25-2.25l3.276-3.276a4.5 4.5 0 0 0-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437 1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008Z"/>)

      "photo" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H3.75A1.5 1.5 0 0 0 2.25 6v12a1.5 1.5 0 0 0 1.5 1.5Zm10.5-11.25h.008v.008h-.008V8.25Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z"/>)

      "beer-mug" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M17 11h1a3 3 0 0 1 0 6h-1"/><path stroke-linecap="round" stroke-linejoin="round" d="M9 12v6"/><path stroke-linecap="round" stroke-linejoin="round" d="M13 12v6"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 7.5c-1 0-1.44.5-3 .5s-2-.5-3-.5-1.72.5-2.5.5a2.5 2.5 0 0 1 0-5c.78 0 1.57.5 2.5.5C9.44 3.5 10 3 11 3s1.56.5 3 .5c.78 0 1.5-.5 2.5-.5a2.5 2.5 0 0 1 0 5c-.78 0-1.5-.5-2.5-.5Z"/><path stroke-linecap="round" stroke-linejoin="round" d="M5 8v12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V8"/>)

      "question-mark-circle" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 5.25h.008v.008H12v-.008Z"/>)

      "light-bulb" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 18v-5.25m0 0a6.01 6.01 0 0 0 1.5-.189m-1.5.189a6.01 6.01 0 0 1-1.5-.189m3.75 7.439a4.5 4.5 0 0 0 6.75-3.75V12a7.5 7.5 0 0 0-15 0v4.5a4.5 4.5 0 0 0 6.75 3.75M9.75 9h.008v.008H9.75V9Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm4.125 4.5h.008v.008H13.5V13.5Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z"/>)

      "arrow-down-tray" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"/>)

      "arrow-left" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"/>)

      "arrow-up" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5"/>)

      "arrow-down" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5"/>)

      "bars-3" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"/>)

      "camera" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M6.827 6.175A2.31 2.31 0 0 1 5.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 0 0-1.134-.175 2.31 2.31 0 0 1-1.64-1.055l-.822-1.316a2.192 2.192 0 0 0-1.736-1.039 48.774 48.774 0 0 0-5.232 0 2.192 2.192 0 0 0-1.736 1.039l-.821 1.316Z"/><path stroke-linecap="round" stroke-linejoin="round" d="M16.5 12.75a4.5 4.5 0 1 1-9 0 4.5 4.5 0 0 1 9 0Z"/>)

      "link" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244"/>)

      "document-chart-bar" ->
        ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"/>)
    end
  end

  attr :id, :string, default: "confirm-modal"
  attr :title, :string, default: "Bestätigung"
  attr :message, :string, default: "Bist du sicher?"
  attr :confirm_label, :string, default: "Bestätigen"
  attr :confirm_class, :string, default: "btn-error"
  attr :confirm_event, :string, default: "confirm"
  attr :cancel_event, :string, default: "cancel_confirm"
  attr :show, :boolean, default: false
  slot :inner_block, required: false

  def confirm_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <dialog
        id={@id}
        phx-hook="Dialog"
        data-cancel-event={@cancel_event}
        class="m-auto rounded-box bg-base-100 p-6 shadow-xl w-[calc(100%-2rem)] sm:w-auto sm:min-w-sm max-w-md"
      >
        <div class="flex items-start justify-between gap-4">
          <h3 class="text-lg font-bold">{@title}</h3>
          <button
            type="button"
            phx-click={@cancel_event}
            aria-label="Schließen"
            class="btn btn-circle btn-ghost btn-sm shrink-0"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <%= if @inner_block do %>
          <div class="pt-4">
            {render_slot(@inner_block)}
          </div>
        <% else %>
          <p class="pt-4">{@message}</p>
        <% end %>
        <div class="flex mt-6">
          <button
            phx-click={@confirm_event}
            class={["btn btn-sm w-full sm:w-auto sm:ml-auto min-h-11 sm:min-h-0", @confirm_class]}
          >
            {@confirm_label}
          </button>
        </div>
      </dialog>
    <% end %>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(PubQuizzerWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(PubQuizzerWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # --- Quiz helpers ---

  @doc """
  Converts a 0-based index to a letter: 0 → "A", 1 → "B", etc.
  Returns "?" for out-of-range indices.
  """
  def letter_for_index(index) do
    Enum.at(~w(A B C D E F), index, "?")
  end

  @doc """
  Derives the thumbnail URL for a given upload path.

  `/uploads/foo.jpg` → `/uploads/thumb_foo.jpg`. Returns `nil` for `nil`.
  Used in `srcset` to serve smaller images to small displays.
  """
  def thumbnail_url(nil), do: nil

  def thumbnail_url("/uploads/" <> rest), do: "/uploads/thumb_#{rest}"

  def thumbnail_url(other), do: other

  @doc """
  Builds the responsive `srcset` attribute value for a question image: a 768w
  thumbnail followed by the full 1920w original. Centralized so the offered
  resolutions stay consistent across all consumers.
  """
  def srcset_for(url), do: "#{thumbnail_url(url)} 768w, #{url} 1920w"

  attr :question, :map, required: true

  @doc """
  Renders the answer-option rows for a question (large, beamer-friendly).
  Shared between the "with image" and "no image" layouts in the host console
  question phase so the option markup lives in one place.
  """
  def question_options(assigns) do
    ~H"""
    <%= for {option, idx} <- Enum.with_index(@question.options) do %>
      <div class="p-6 rounded-lg bg-base-300 text-3xl qa-option flex items-center gap-4">
        <span class="font-mono font-bold shrink-0">{letter_for_index(idx)}.</span>
        <span class="break-words flex-1"><.multiline_text text={option["text"]} /></span>
        <%= if opt_img = option["image"] do %>
          <img
            src={thumbnail_url(opt_img)}
            srcset={srcset_for(opt_img)}
            sizes="80px"
            alt=""
            class="h-20 w-20 object-cover rounded shrink-0"
          />
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :options, :list, required: true
  attr :correct_index, :integer, default: nil
  attr :image_overrides, :map, default: %{}
  attr :class, :string, default: nil

  @doc """
  Renders answer options as a responsive grid of image cards for the
  "answer_cards" slide layout. Each card shows the option's image (or a
  placeholder) with the letter + text below. Shared between the host console
  and the editor preview. Pass `correct_index` to highlight the right answer
  (preview only — the host question phase omits it).
  """
  def answer_cards(assigns) do
    ~H"""
    <div class={["grid grid-cols-2 sm:grid-cols-4 gap-4 sm:gap-6", @class]}>
      <%= for {option, idx} <- Enum.with_index(@options) do %>
        <% is_correct = @correct_index == idx %>
        <% opt_img = Map.get(@image_overrides, idx) || option["image"] %>
        <div class="flex flex-col gap-2 sm:gap-3">
          <%= if opt_img do %>
            <div class={[
              "aspect-[3/4] rounded overflow-hidden",
              is_correct && "ring-4 ring-success"
            ]}>
              <img src={opt_img} alt="" class="w-full h-full object-cover" />
            </div>
          <% else %>
            <div class={[
              "aspect-[3/4] rounded bg-base-300/60 flex items-center justify-center text-base-content/30",
              is_correct && "ring-4 ring-success"
            ]}>
              <.icon name="hero-photo" class="size-10 sm:size-12" />
            </div>
          <% end %>
          <div class={[
            "text-xl sm:text-2xl flex items-start gap-2",
            is_correct && "text-success font-semibold"
          ]}>
            <span class="font-mono font-bold shrink-0">{letter_for_index(idx)}</span>
            <span class="break-words flex-1"><.multiline_text text={option["text"]} /></span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :img, :string, required: true
  attr :class, :string, default: nil
  attr :sizes, :string, default: "(max-width: 640px) 100vw, 768px"
  attr :rest, :global, include: ~w(loading)

  @doc """
  Renders a single question image with a responsive thumbnail srcset.
  Shared across the slide layouts and the review list so the srcset/alt
  markup lives in exactly one place.
  """
  def question_image(assigns) do
    ~H"""
    <img
      src={@img}
      srcset={srcset_for(@img)}
      sizes={@sizes}
      alt="Fragebild"
      class={["rounded-lg", @class]}
      {@rest}
    />
    """
  end

  attr :question, :map, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  @doc """
  Renders the question slide exactly as the host beamer shows it during the
  question phase. Shared between the host console and the editor preview so
  the two can never drift. Never highlights the correct answer.
  """
  def question_slide(assigns) do
    ~H"""
    <div class={["card bg-base-200 overflow-hidden", @class]}>
      <div class="card-body" id={@id}>
        <% layout = @question[:layout] || "image_side" %>
        <% q_images = @question[:images] || [] %>
        <% with_images? = q_images != [] %>

        <%= cond do %>
          <% layout == "answer_cards" -> %>
            <h4 class="card-title text-3xl break-words leading-relaxed mb-4">
              <span class="w-full min-w-0"><.multiline_text text={@question.prompt} /></span>
            </h4>
            <.answer_cards options={@question.options} />
          <% layout == "image_side" and with_images? -> %>
            <% position = @question[:image_position] || "left" %>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
              <h4 class="card-title text-3xl break-words leading-relaxed sm:col-span-2">
                <span class="w-full min-w-0"><.multiline_text text={@question.prompt} /></span>
              </h4>
              <div class={["space-y-4 sm:col-span-1", position == "left" && "sm:order-2"]}>
                <.question_options question={@question} />
              </div>
              <div class={["flex flex-col gap-4 sm:col-span-1", position == "left" && "sm:order-1"]}>
                <%= for img <- q_images do %>
                  <.question_image img={img} class="w-full h-auto object-contain" />
                <% end %>
              </div>
            </div>
          <% layout == "image_top" and with_images? -> %>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-6 items-center mb-6">
              <div class="sm:col-span-1 flex flex-col gap-4">
                <%= for img <- q_images do %>
                  <.question_image img={img} class="w-full object-contain" />
                <% end %>
              </div>
              <h4 class="card-title text-3xl break-words leading-relaxed sm:col-span-2">
                <span class="w-full min-w-0"><.multiline_text text={@question.prompt} /></span>
              </h4>
            </div>
            <div class="space-y-4">
              <.question_options question={@question} />
            </div>
          <% true -> %>
            <h4 class="card-title text-3xl break-words leading-relaxed">
              <span class="w-full min-w-0"><.multiline_text text={@question.prompt} /></span>
            </h4>
            <div class="space-y-4 mt-6">
              <.question_options question={@question} />
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :rank, :integer, required: true
  attr :id, :any, required: true
  attr :name, :string, required: true
  attr :score, :integer, required: true
  attr :size, :string, default: "lg", values: ["lg", "sm"]
  attr :rest, :global
  slot :inner_block, required: false

  @doc """
  Renders a single ranked standing row with gold/silver/bronze styling.
  Used in both host lobby and team lobby for round reveal and final standings.
  """
  def podium_row(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex items-center gap-6 rounded-2xl px-8 py-6 shadow-lg transition-colors duration-300",
        @size == "sm" && "gap-3 rounded-lg px-4 py-3 shadow-sm",
        @rank == 0 && "bg-warning/20 border-2 border-warning",
        @rank == 0 && @size == "sm" && "bg-warning/20 border border-warning",
        @rank == 1 && "bg-base-300",
        @rank == 2 && "bg-amber-800/20",
        @rank > 2 && "bg-base-200"
      ]}
      {@rest}
    >
      <span class={[
        "flex items-center justify-center rounded-full text-3xl font-bold shrink-0",
        @size == "sm" && "w-8 h-8 text-base",
        @size == "lg" && "w-16 h-16 text-3xl",
        @rank == 0 && "bg-warning text-warning-content",
        @rank == 1 && "bg-base-content/20 text-base-content",
        @rank == 2 && "bg-amber-800 text-amber-100",
        @rank > 2 && "bg-base-content/20 text-base-content"
      ]}>
        {@rank + 1}
      </span>
      <span class={[
        "flex-1 font-bold",
        @size == "sm" && "text-sm",
        @size == "lg" && "text-3xl",
        @rank == 0 && "text-base-content"
      ]}>
        {@name}
        <slot />
      </span>
      <span class={[
        "badge font-bold",
        @size == "sm" && "text-sm py-1 px-3",
        @size == "lg" && "text-2xl py-4 px-6",
        @rank == 0 && "badge-warning",
        @rank == 1 && "badge-primary",
        @rank == 2 && "badge-primary",
        @rank > 2 && "badge-ghost"
      ]}>
        {@score}
      </span>
    </div>
    """
  end
end
