defmodule PubQuizzerWeb.Admin.QuestionLive do
  use PubQuizzerWeb, :live_view

  require Logger

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Question
  alias PubQuizzer.Quiz.Topic
  embed_templates "question_live/*"

  @option_count 4
  @empty_options [%{"text" => ""}, %{"text" => ""}, %{"text" => ""}, %{"text" => ""}]

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :index -> shell(assigns)
      :new -> new(assigns)
      :edit -> shell(assigns)
    end
  end

  @doc "Full-screen image viewer dialog. Renders nothing when `url` is nil."
  attr :url, :string, default: nil

  def image_lightbox(%{url: nil} = assigns), do: ~H""

  def image_lightbox(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4"
      phx-click="close_image"
    >
      <div class="relative max-w-4xl max-h-[90vh]" phx-click.stop>
        <img src={@url} class="max-w-full max-h-[90vh] object-contain rounded" />
        <button
          type="button"
          phx-click="close_image"
          class="btn btn-circle btn-sm absolute top-2 right-2"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  @doc "Validation error banner. Renders nothing until the form has been submitted with errors."
  attr :form, :any, required: true
  attr :submitted, :boolean, default: false

  def form_errors(%{submitted: false} = assigns), do: ~H""

  def form_errors(%{form: %{errors: []}} = assigns), do: ~H""

  def form_errors(assigns) do
    ~H"""
    <div class="alert alert-error py-2 px-3 text-sm">
      <.icon name="hero-exclamation-circle" class="size-4" />
      <span>
        <%= for {msg, _} <- @form[:prompt].errors do %>
          <span>{msg}</span>
        <% end %>
        <%= for {msg, _} <- @form[:options].errors do %>
          <span>{msg}</span>
        <% end %>
        <%= for {msg, _} <- @form[:correct_index].errors do %>
          <span>{msg}</span>
        <% end %>
      </span>
    </div>
    """
  end

  @doc "Slide-layout picker: chooses how the question renders on the beamer."
  attr :form, :any, required: true

  def layout_picker(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between gap-3 px-3 sm:px-0">
        <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
          Layout
        </span>
        <div class="flex items-center gap-1.5" role="radiogroup" aria-label="Layout">
          <% current = @form[:layout].value || "image_side" %>

          <.layout_thumb current={current} value="image_side" label="Bild + Text">
            <div class="flex gap-0.5 h-full">
              <div class="w-1/2 rounded-sm bg-current opacity-30"></div>
              <div class="w-1/2 flex flex-col gap-0.5 justify-center">
                <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
                <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
                <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
              </div>
            </div>
          </.layout_thumb>

          <.layout_thumb current={current} value="answer_cards" label="Antwort-Bilder">
            <div class="h-1.5 w-full rounded-sm bg-current opacity-70"></div>
            <div class="mt-1 grid grid-cols-4 gap-0.5 flex-1">
              <div class="rounded-sm bg-current opacity-30"></div>
              <div class="rounded-sm bg-current opacity-30"></div>
              <div class="rounded-sm bg-current opacity-30"></div>
              <div class="rounded-sm bg-current opacity-30"></div>
            </div>
          </.layout_thumb>

          <.layout_thumb current={current} value="image_top" label="Bild oben">
            <div class="flex gap-0.5">
              <div class="w-1/3 h-4 rounded-sm bg-current opacity-30"></div>
              <div class="w-2/3 flex flex-col gap-0.5 justify-center">
                <div class="h-1 w-full rounded-sm bg-current opacity-70"></div>
                <div class="h-1 w-full rounded-sm bg-current opacity-70"></div>
              </div>
            </div>
            <div class="mt-1 space-y-0.5">
              <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
              <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
            </div>
          </.layout_thumb>
        </div>
      </div>

      <%= if (@form[:layout].value || "image_side") == "image_side" do %>
        <div class="flex items-center justify-between px-3 sm:px-0">
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Bildposition
          </span>
          <% position = @form[:image_position].value || "left" %>
          <div class="relative grid grid-cols-2 bg-base-200 rounded-lg p-0.5">
            <span
              aria-hidden="true"
              class={[
                "absolute inset-y-0.5 left-0.5 w-[calc(50%-0.125rem)] rounded-md bg-base-100 shadow-sm transition-transform duration-200 ease-out",
                position == "right" && "translate-x-full"
              ]}
            ></span>
            <label class={[
              "relative z-10 px-3 py-1.5 text-sm font-medium rounded-md cursor-pointer transition-colors text-center",
              position == "left" && "text-base-content",
              position != "left" && "text-base-content/60 hover:text-base-content"
            ]}>
              <input
                type="radio"
                name="question[image_position]"
                value="left"
                class="sr-only"
                checked={position == "left"}
              /> Links
            </label>
            <label class={[
              "relative z-10 px-3 py-1.5 text-sm font-medium rounded-md cursor-pointer transition-colors text-center",
              position == "right" && "text-base-content",
              position != "right" && "text-base-content/60 hover:text-base-content"
            ]}>
              <input
                type="radio"
                name="question[image_position]"
                value="right"
                class="sr-only"
                checked={position == "right"}
              /> Rechts
            </label>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :current, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  def layout_thumb(assigns) do
    ~H"""
    <label class={[
      "flex flex-col items-center gap-1 cursor-pointer rounded-lg p-1.5 transition-colors",
      @current == @value && "bg-base-200 ring-2 ring-primary/60",
      @current != @value && "hover:bg-base-200/60"
    ]}>
      <input
        type="radio"
        name="question[layout]"
        value={@value}
        class="sr-only"
        checked={@current == @value}
      />
      <div class={[
        "w-16 h-10 rounded border bg-base-100 p-1 flex flex-col text-base-content",
        @current == @value && "border-primary/50",
        @current != @value && "border-base-content/20"
      ]}>
        {render_slot(@inner_block)}
      </div>
      <span class={[
        "text-[10px] font-medium leading-none",
        @current == @value && "text-base-content",
        @current != @value && "text-base-content/60"
      ]}>{@label}</span>
    </label>
    """
  end

  @doc "Published/draft status toggle card. Shared by the new and edit forms."
  attr :form, :any, required: true

  def status_card(assigns) do
    ~H"""
    <div class={[
      "rounded-xl border px-4 py-2 sm:p-4 transition-colors",
      if(@form[:status].value == "published",
        do: "border-success/40 bg-success/10",
        else: "border-warning/40 bg-warning/10"
      )
    ]}>
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3 min-w-0">
          <div class={[
            "size-9 rounded-lg grid place-items-center shrink-0 transition-colors",
            if(@form[:status].value == "published",
              do: "bg-success/20 text-success",
              else: "bg-warning/20 text-warning"
            )
          ]}>
            <.icon
              name={
                if @form[:status].value == "published",
                  do: "hero-check-circle",
                  else: "hero-pencil"
              }
              class="size-5"
            />
          </div>
          <div class="min-w-0">
            <div class="text-sm font-semibold leading-tight">
              {if @form[:status].value == "published", do: "Veröffentlicht", else: "Entwurf"}
            </div>
            <div class="text-xs text-base-content/60 leading-tight mt-0.5 hidden sm:block">
              {if @form[:status].value == "published",
                do: "Sichtbar im Live-Quiz",
                else: "Nicht im Live-Quiz"}
            </div>
          </div>
        </div>
        <label class="cursor-pointer shrink-0">
          <input type="hidden" name="question[published]" value="false" />
          <input
            type="checkbox"
            name="question[published]"
            value="true"
            checked={@form[:status].value == "published"}
            class="toggle toggle-success"
          />
        </label>
      </div>
    </div>
    """
  end

  @doc "Prompt textarea, question-image upload zone, and layout picker."
  attr :form, :any, required: true
  attr :uploads, :map, required: true
  attr :question, :any, default: nil

  def prompt_card(assigns) do
    ~H"""
    <% existing_images = (@question && @question.images) || [] %>
    <div class="card sm:bg-base-100 sm:border sm:border-base-300 sm:shadow-md">
      <div class="card-body p-0 sm:p-5 gap-3 sm:gap-4">
        <div class="flex items-center justify-between px-3 sm:px-0">
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Frage
          </span>
          <%= if @form[:correct_index].value != nil do %>
            <span class="text-xs text-base-content/50">
              Richtige Antwort:
              <span class="font-mono font-bold text-success">
                {String.capitalize(letter_for_index(@form[:correct_index].value))}
              </span>
            </span>
          <% end %>
        </div>
        <textarea
          name="question[prompt]"
          id="question_prompt"
          phx-hook="AutoResize"
          class="w-full text-lg sm:text-2xl font-semibold leading-relaxed bg-base-100 border-2 border-base-300 rounded-lg outline-none resize-none placeholder:text-base-content/30 focus:outline-none px-3 py-2 whitespace-pre-wrap"
          placeholder="Wie lautet die Frage?"
          rows="3"
        ><%= @form[:prompt].value || "" %></textarea>

        <div
          id="image-upload-zone"
          phx-drop-target={@uploads.image.ref}
          class={[
            "rounded-lg border-2 border-dashed transition-colors",
            @uploads.image.entries != [] && "border-primary bg-primary/5",
            @uploads.image.entries == [] && "border-base-300 hover:border-base-content/30",
            existing_images == [] && "hidden sm:block"
          ]}
        >
          <div class="p-1">
            <%= if existing_images != [] or @uploads.image.entries != [] do %>
              <div class="flex flex-wrap justify-center gap-2">
                <%= for {img, idx} <- Enum.with_index(existing_images) do %>
                  <div class="relative inline-block">
                    <img
                      src={img}
                      alt="Aktuelles Bild"
                      phx-click="view_image"
                      phx-value-url={img}
                      class="block rounded-lg max-h-36 sm:max-h-56 max-w-full object-contain cursor-zoom-in"
                    />
                    <button
                      type="button"
                      phx-click="remove_image"
                      phx-value-index={idx}
                      class="btn btn-xs btn-circle absolute -top-2 -right-2 select-none"
                    >×</button>
                  </div>
                <% end %>
                <%= for entry <- @uploads.image.entries do %>
                  <div
                    id={"upload-entry-#{entry.ref}"}
                    phx-update="ignore"
                    phx-hook="ReportUploadedImage"
                    class="relative inline-block"
                  >
                    <img
                      id={"img-preview-#{entry.ref}"}
                      phx-hook="Phoenix.LiveImgPreview"
                      data-phx-entry-ref={entry.ref}
                      data-phx-upload-ref={@uploads.image.ref}
                      alt="Vorschau"
                      class="block rounded-lg max-h-36 sm:max-h-56 max-w-full object-contain"
                    />
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      class="btn btn-xs btn-circle absolute -top-2 -right-2 select-none"
                    >×</button>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="flex flex-row sm:flex-col items-center justify-center gap-1.5 sm:gap-1 py-1.5 sm:py-2 text-base-content/40">
                <.icon name="hero-photo" class="size-5 sm:size-6" />
                <span class="text-xs">Keine Bilder ausgewählt</span>
              </div>
            <% end %>
          </div>
          <label class="hidden sm:flex items-center justify-center gap-2 px-3 py-1.5 cursor-pointer text-xs text-base-content/70 hover:text-base-content hover:bg-base-300/50 transition-colors rounded-b-lg border-t border-base-300 select-none">
            <.icon name="hero-photo" class="size-4" />
            <span>Bilder hinzufügen</span>
            <.live_file_input upload={@uploads.image} class="sr-only" />
          </label>
        </div>

        <.layout_picker form={@form} />
      </div>
    </div>
    """
  end

  @doc "The four answer-option rows with click-to-select and drag-to-sort."
  attr :form, :any, required: true
  attr :uploads, :map, required: true
  attr :option_image_previews, :map, default: %{}

  def option_rows(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-2 px-3 sm:px-0">
        <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
          Antwortoptionen
        </span>
        <span class="text-xs text-base-content/50">
          Klick zum Auswählen<span class="hidden sm:inline"> · Ziehen zum Sortieren</span>
        </span>
      </div>

      <div
        id="question-options"
        class="space-y-2"
        phx-hook="OptionSorter"
        data-correct-index={@form[:correct_index].value}
      >
        <%= for i <- 0..3 do %>
          <% opt_val = Phoenix.HTML.Form.input_value(@form, :options) |> Enum.at(i, %{}) %>
          <% opt_text = (is_map(opt_val) && Map.get(opt_val, "text")) || "" %>
          <% opt_img = (is_map(opt_val) && Map.get(opt_val, "image")) || nil %>
          <% is_correct = @form[:correct_index].value == i %>
          <div
            data-index={i}
            phx-click="select_correct"
            phx-value-index={i}
            class={[
              "opt-row group relative rounded-lg sm:rounded-xl p-1.5 sm:p-4 transition-all cursor-pointer sm:border-2 sm:shadow-md",
              is_correct && "bg-success/10 sm:border-success sm:shadow-lg",
              !is_correct &&
                "bg-base-100 sm:border-base-300 sm:hover:border-base-content/40 sm:hover:shadow-lg"
            ]}
          >
            <div class="flex items-start gap-2 sm:gap-3">
              <div class="hidden sm:flex flex-col items-center gap-0.5 pt-2 text-base-content/30 cursor-grab select-none drag-handle hover:text-base-content/60">
                <span class="leading-none text-lg">⠿</span>
              </div>

              <div class={[
                "font-mono font-bold text-lg sm:text-xl w-6 sm:w-7 pt-2 shrink-0 text-center",
                is_correct && "text-success",
                !is_correct && "text-base-content/50"
              ]}>
                {String.capitalize(letter_for_index(i))}
              </div>

              <textarea
                name={"question[options][#{i}]"}
                id={"question_options_#{i}"}
                data-option-text
                phx-hook="AutoResize"
                onclick="event.stopPropagation()"
                class="flex-1 min-w-0 bg-base-100 border-2 border-base-300 rounded-lg outline-none resize-none text-base sm:text-lg leading-relaxed placeholder:text-base-content/30 focus:outline-none px-2 py-1.5 min-h-[3.75rem] whitespace-pre-wrap"
                placeholder={"Option #{String.capitalize(letter_for_index(i))}"}
                rows="2"
              ><%= opt_text %></textarea>

              <%= if @option_image_previews[i] == nil and opt_img == nil do %>
                <label
                  for={live_option_upload(assigns, i).ref}
                  onclick="event.stopPropagation()"
                  title="Bild hinzufügen"
                  class="hidden sm:inline-flex shrink-0 mt-2 items-center justify-center size-10 rounded-md border border-base-300 text-base-content/50 bg-base-200 hover:bg-base-300 hover:text-base-content cursor-pointer transition-colors select-none"
                >
                  <.icon name="hero-photo" class="size-6" />
                </label>
              <% end %>

              <div class={[
                "hidden sm:block pt-2 shrink-0 transition-opacity",
                is_correct && "opacity-100",
                !is_correct && "opacity-0 group-hover:opacity-30"
              ]}>
                <.icon
                  name="hero-check-circle"
                  class={[
                    "size-5",
                    is_correct && "text-success",
                    !is_correct && "text-base-content/40"
                  ]}
                />
              </div>
            </div>

            <div
              id={"option-image-zone-#{i}"}
              data-option-index={i}
              phx-hook="OptionImagePreview"
              phx-drop-target={live_option_upload(assigns, i).ref}
              class="mt-2 ml-8 sm:ml-16"
            >
              <.live_file_input upload={live_option_upload(assigns, i)} class="sr-only" />

              <%= cond do %>
                <% preview = @option_image_previews[i] -> %>
                  <button
                    type="button"
                    phx-click="view_image"
                    phx-value-url={preview}
                    class="sm:hidden btn btn-xs btn-ghost gap-1 select-none"
                  >
                    <.icon name="hero-photo" class="size-4" />
                    <span class="text-xs">Bild</span>
                  </button>
                  <div class="hidden sm:block relative w-fit">
                    <img src={preview} class="h-40 max-w-full rounded border border-base-300" />
                    <button
                      type="button"
                      phx-click="cancel_option_upload"
                      phx-value-index={i}
                      class="btn btn-xs btn-circle absolute -top-2 -right-2 select-none"
                    >×</button>
                  </div>
                <% img = opt_img -> %>
                  <button
                    type="button"
                    phx-click="view_image"
                    phx-value-url={img}
                    class="sm:hidden btn btn-xs btn-ghost gap-1 select-none"
                  >
                    <.icon name="hero-photo" class="size-4" />
                    <span class="text-xs">Bild</span>
                  </button>
                  <div class="hidden sm:block relative w-fit group">
                    <img src={img} class="h-40 max-w-full rounded border border-base-300" />
                    <button
                      type="button"
                      phx-click="remove_option_image"
                      phx-value-index={i}
                      class="btn btn-xs btn-circle absolute -top-2 -right-2 opacity-0 group-hover:opacity-100 select-none"
                    >×</button>
                  </div>
                <% true -> %>
                  <% :ok %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc "PowerPoint-style ordered rail: numbered, draggable question list."
  attr :topic, :any, required: true
  attr :questions, :any, required: true
  attr :search, :string, required: true
  attr :first_question_id, :any, required: true
  attr :last_question_id, :any, required: true
  attr :selected_id, :any, default: nil

  def question_rail(assigns) do
    ~H"""
    <div
      id="questions"
      phx-update="stream"
      phx-hook="QuestionSorter"
      class="flex flex-col gap-1.5 lg:min-h-0 lg:flex-1 lg:overflow-y-auto lg:pr-1 lg:pb-6"
    >
      <div
        :for={{id, q} <- @questions}
        id={id}
        class={[
          "q-card relative cursor-pointer overflow-hidden rounded-xl border-2 px-3.5 py-4 transition-all duration-150",
          if(@selected_id == q.id,
            do: "border-primary bg-primary/10",
            else: "border-base-300 bg-base-200 hover:border-base-content/30 hover:bg-base-300/50"
          )
        ]}
      >
        <% selected = @selected_id == q.id %>
        <.link
          patch={~p"/admin/topics/#{@topic.id}/questions/#{q.id}/edit"}
          class="absolute inset-0 z-[1] rounded-xl"
        >
          <span class="sr-only">Frage {q.position + 1} öffnen</span>
        </.link>
        <div class="flex items-start gap-2.5">
          <span class={[
            "mt-0.5 grid size-6 shrink-0 place-items-center rounded-full font-mono text-xs font-semibold leading-none tabular-nums",
            if(selected,
              do: "bg-primary text-primary-content",
              else: "bg-base-300 text-base-content/60"
            )
          ]}>
            {q.position + 1}
          </span>
          <div class="min-w-0 flex-1">
            <span class="block py-0.5 pr-1">
              <span class="font-medium break-words line-clamp-5 text-sm leading-snug">
                {q.prompt}
              </span>
            </span>
            <div class="mt-1 flex items-center gap-1.5 text-[11px] text-base-content/50">
              <span class={[
                "size-1.5 rounded-full",
                if(q.status == "published", do: "bg-success", else: "bg-warning")
              ]}></span>
              <span>{if q.status == "published", do: "Live", else: "Entwurf"}</span>
              <%= if (q.images || []) != [] do %>
                <span class="inline-flex items-center gap-0.5">
                  <.icon name="hero-photo" class="size-3" /> {length(q.images)}
                </span>
              <% end %>
              <span class="text-base-content/30">·</span>
              <span>{Calendar.strftime(q.updated_at, "%d.%m.%y")}</span>
            </div>
            <div class="mt-1.5 flex items-center gap-0.5">
              <%= if @search == "" do %>
                <button
                  type="button"
                  phx-click="move_up"
                  phx-value-id={q.id}
                  disabled={q.id == @first_question_id}
                  aria-label="Nach oben verschieben"
                  class="btn btn-xs btn-ghost btn-square relative z-[2]"
                >
                  <.icon name="hero-arrow-up" class="size-3.5" />
                </button>
                <button
                  type="button"
                  phx-click="move_down"
                  phx-value-id={q.id}
                  disabled={q.id == @last_question_id}
                  aria-label="Nach unten verschieben"
                  class="btn btn-xs btn-ghost btn-square relative z-[2]"
                >
                  <.icon name="hero-arrow-down" class="size-3.5" />
                </button>
                <div
                  aria-hidden="true"
                  title="Ziehen zum Sortieren"
                  class="drag-handle relative z-[2] hidden lg:flex flex-col items-center justify-center px-1 text-base-content/30 cursor-grab select-none hover:text-base-content/60"
                >
                  <span class="leading-none text-lg">⠿</span>
                </div>
              <% end %>
              <div class="flex-1"></div>
              <button
                type="button"
                phx-click="ask_delete"
                phx-value-id={q.id}
                aria-label="Löschen"
                class="btn btn-xs btn-ghost btn-square relative z-[2] text-error hover:bg-error/10"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "Editor pane: toolbar plus the question form content."
  attr :form, :any, required: true
  attr :question, :any, required: true
  attr :uploads, :map, required: true
  attr :option_image_previews, :map, required: true
  attr :form_submitted, :boolean, required: true

  def editor_pane(assigns) do
    ~H"""
    <div class="mb-3 flex items-center justify-between gap-2 lg:pt-2">
      <h2 class="min-w-0 truncate text-lg font-bold leading-tight">
        Frage {@question.position + 1}
      </h2>
      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click="toggle_preview"
          class="btn btn-soft btn-sm gap-1 hidden sm:inline-flex"
        >
          <.icon name="hero-eye" class="size-4" /> Vorschau
        </button>
        <button type="submit" form="question-form" class="btn btn-primary btn-sm gap-1">
          <span class="loading loading-spinner loading-xs hidden [.phx-submit-loading_&]:inline-block"></span>
          <.icon name="hero-check-circle" class="size-4 [.phx-submit-loading_&]:hidden" /> Speichern
        </button>
      </div>
    </div>

    <div class="bg-base-200 rounded-2xl p-1.5 sm:p-6 space-y-5 border border-base-300 min-w-0">
      <%!-- Hidden correct index — driven by click-to-select on option cards --%>
      <input type="hidden" name="question[correct_index]" value={@form[:correct_index].value} />

      <.form_errors form={@form} submitted={@form_submitted} />
      <.prompt_card form={@form} uploads={@uploads} question={@question} />
      <.option_rows
        form={@form}
        uploads={@uploads}
        option_image_previews={@option_image_previews}
      />
    </div>
    """
  end

  @doc "Right-hand meta pane: status toggle and edit history."
  attr :form, :any, required: true
  attr :versions, :list, required: true

  def meta_pane(assigns) do
    ~H"""
    <div class="space-y-3 lg:pt-5">
      <.status_card form={@form} />

      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-4 gap-3">
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-base-content/80">Bearbeitungsverlauf</h3>
            <span class="text-xs text-base-content/50">{length(@versions)} Versionen</span>
          </div>
          <%= if @versions == [] do %>
            <p class="text-sm text-base-content/70 italic">Noch keine Versionen.</p>
          <% else %>
            <div class="space-y-2">
              <%= for {version, diffs} <- @versions do %>
                <div class="rounded-lg border border-base-300 bg-base-100 px-3 py-2">
                  <div class="flex items-center gap-2">
                    <div class="avatar avatar-placeholder">
                      <div class="bg-primary text-primary-content rounded-full w-7">
                        <span class="text-xs font-semibold">
                          {String.at((version.user && version.user.name) || "?", 0)}
                        </span>
                      </div>
                    </div>
                    <div class="min-w-0 flex-1">
                      <span class="font-medium text-sm block truncate">
                        {(version.user && version.user.name) || "Unbekannt"}
                      </span>
                      <span class="text-xs text-base-content/70">
                        {Calendar.strftime(version.inserted_at, "%d.%m.%y %H:%M")}
                      </span>
                    </div>
                  </div>
                  <%= if diffs != [] do %>
                    <ul class="mt-2 space-y-1 text-xs text-base-content/80 border-t border-base-300 pt-2">
                      <%= for diff <- diffs do %>
                        <li class="flex items-start gap-1">
                          <.icon
                            name="hero-pencil"
                            class="size-3 mt-0.5 shrink-0 text-base-content/60"
                          />
                          <%= case diff.field do %>
                            <% :prompt -> %>
                              <span class="font-semibold">Frage geändert</span>
                            <% :options -> %>
                              <span class="font-semibold">Optionen geändert</span>
                            <% :correct_index -> %>
                              <span class="font-semibold">Antwort:</span>
                              {String.capitalize(letter_for_index(diff.old || 0))} → {String.capitalize(
                                letter_for_index(diff.new || 0)
                              )}
                            <% :image -> %>
                              <%= cond do %>
                                <% is_nil(diff.old) and not is_nil(diff.new) -> %>
                                  <span class="font-semibold">Bild hinzugefügt</span>
                                <% not is_nil(diff.old) and is_nil(diff.new) -> %>
                                  <span class="font-semibold">Bild entfernt</span>
                                <% true -> %>
                                  <span class="font-semibold">Bild geändert</span>
                              <% end %>
                            <% :images -> %>
                              <%= cond do %>
                                <% (diff.old || []) == [] and (diff.new || []) != [] -> %>
                                  <span class="font-semibold">Bild hinzugefügt</span>
                                <% (diff.old || []) != [] and (diff.new || []) == [] -> %>
                                  <span class="font-semibold">Bild entfernt</span>
                                <% true -> %>
                                  <span class="font-semibold">Bilder geändert</span>
                              <% end %>
                            <% :layout -> %>
                              <span class="font-semibold">Layout:</span>
                              {diff.old || "image_side"} → {diff.new}
                          <% end %>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:confirm_action, nil)
      |> assign(:pending_delete_id, nil)
      |> assign(:editing_topic, false)
      |> assign(:topic_form, nil)
      |> assign(:search, "")
      |> assign(:option_image_previews, %{})
      |> assign(:preview_uploads, %{})
      |> assign(:show_preview, false)
      |> assign(:viewing_image, nil)
      |> assign(:rail_collapsed, false)
      |> assign(:meta_collapsed, false)
      |> allow_upload(:image,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 4,
        max_file_size: 20_000_000,
        auto_upload: true
      )

    socket =
      Enum.reduce(0..(@option_count - 1), socket, fn i, acc ->
        allow_upload(acc, :"option_image_#{i}",
          accept: ~w(.jpg .jpeg .png .gif .webp),
          max_entries: 1,
          max_file_size: 20_000_000,
          auto_upload: true
        )
      end)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"topic_id" => topic_id}) do
    topic = Quiz.get_topic!(topic_id)
    questions = rail_questions(socket, topic)

    selected =
      case socket.assigns[:question] do
        %Question{id: id} = q ->
          if Enum.any?(questions, &(&1.id == id)), do: q, else: List.first(questions)

        _ ->
          List.first(questions)
      end

    socket
    |> assign(:page_title, topic.name)
    |> assign(:editing_topic, false)
    |> assign(:topic_form, nil)
    |> assign_rail(topic, questions)
    |> load_editor(selected)
  end

  defp apply_action(socket, :new, %{"topic_id" => topic_id}) do
    topic = Quiz.get_topic!(topic_id)
    changeset = Question.changeset(%Question{options: @empty_options}, %{correct_index: 0})

    socket
    |> assign(:topic, topic)
    |> assign(:question, nil)
    |> assign(:page_title, "Neue Frage")
    |> assign(:form, to_form(changeset))
    |> assign(:form_submitted, false)
    |> assign(:option_image_previews, %{})
    |> assign(:preview_uploads, %{})
    |> assign(:show_preview, false)
  end

  defp apply_action(socket, :edit, %{"topic_id" => topic_id, "id" => id}) do
    topic = Quiz.get_topic!(topic_id)
    question = Quiz.get_question!(id)
    questions = rail_questions(socket, topic)

    socket
    |> assign(:page_title, "Frage #{question.position + 1} bearbeiten – #{topic.name}")
    |> assign(:editing_topic, false)
    |> assign(:topic_form, nil)
    |> assign_rail(topic, questions)
    |> load_editor(question)
  end

  defp rail_questions(socket, topic) do
    if socket.assigns.search == "" do
      Quiz.list_questions_for_topic(topic.id)
    else
      Quiz.search_questions_for_topic(topic.id, socket.assigns.search)
    end
  end

  defp assign_rail(socket, topic, questions) do
    socket
    |> assign(:topic, topic)
    |> assign(:questions_count, length(questions))
    |> assign(:mini_questions, questions)
    |> assign(:first_question_id, questions |> List.first() |> then(&(&1 && &1.id)))
    |> assign(:last_question_id, questions |> List.last() |> then(&(&1 && &1.id)))
    |> stream(:questions, questions)
  end

  defp load_editor(socket, nil) do
    socket
    |> assign(:question, nil)
    |> assign(:form, nil)
    |> assign(:versions, [])
    |> assign(:form_submitted, false)
    |> assign(:option_image_previews, %{})
    |> assign(:preview_uploads, %{})
    |> assign(:show_preview, false)
  end

  defp load_editor(socket, question) do
    changeset = Question.changeset(question, %{})
    versions = Quiz.list_question_versions(question.id)

    socket
    |> assign(:question, question)
    |> assign(:form, to_form(changeset))
    |> assign(:versions, compute_version_diffs(versions))
    |> assign(:form_submitted, false)
    |> assign(:option_image_previews, %{})
    |> assign(:preview_uploads, %{})
    |> assign(:show_preview, false)
  end

  @impl true
  def handle_event("toggle_rail", _params, socket) do
    {:noreply, update(socket, :rail_collapsed, &(!&1))}
  end

  def handle_event("toggle_meta", _params, socket) do
    {:noreply, update(socket, :meta_collapsed, &(!&1))}
  end

  def handle_event("search", %{"search" => search}, socket) do
    questions =
      if search == "" do
        Quiz.list_questions_for_topic(socket.assigns.topic.id)
      else
        Quiz.search_questions_for_topic(socket.assigns.topic.id, search)
      end

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:questions_count, length(questions))
     |> assign(:mini_questions, questions)
     |> stream(:questions, questions, reset: true)}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:confirm_action, :delete_question)
     |> assign(:pending_delete_id, String.to_integer(id))}
  end

  def handle_event("move_up", %{"id" => id}, socket) do
    {:noreply, move_question(socket, id, -1)}
  end

  def handle_event("move_down", %{"id" => id}, socket) do
    {:noreply, move_question(socket, id, 1)}
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    if socket.assigns.search != "" do
      {:noreply, socket}
    else
      # Drop any id that doesn't parse; reorder_questions rejects mismatched sets,
      # so a tampered payload just no-ops instead of crashing.
      ordered_ids =
        ids
        |> Enum.map(&Integer.parse/1)
        |> Enum.flat_map(fn
          {n, ""} -> [n]
          _ -> []
        end)

      case Quiz.reorder_questions(socket.assigns.topic.id, ordered_ids) do
        {:ok, _questions} -> {:noreply, restream_questions(socket)}
        {:error, :mismatch} -> {:noreply, restream_questions(socket)}
      end
    end
  end

  def handle_event("toggle_preview", _params, socket) do
    {:noreply, assign(socket, :show_preview, !socket.assigns.show_preview)}
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :show_preview, false)}
  end

  def handle_event("confirm_delete", _params, socket) do
    question = Quiz.get_question!(socket.assigns.pending_delete_id)
    {:ok, _} = Quiz.delete_question(question)

    socket =
      socket
      |> assign(:confirm_action, nil)
      |> assign(:pending_delete_id, nil)
      |> restream_questions()
      |> put_flash(:info, "Frage gelöscht.")

    selected? = socket.assigns[:question] != nil and socket.assigns[:question].id == question.id

    cond do
      not selected? ->
        {:noreply, socket}

      socket.assigns.live_action == :edit ->
        {:noreply, push_patch(socket, to: ~p"/admin/topics/#{socket.assigns.topic.id}/questions")}

      true ->
        first = socket.assigns.topic.id |> Quiz.list_questions_for_topic() |> List.first()
        {:noreply, load_editor(socket, first)}
    end
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, socket |> assign(:confirm_action, nil) |> assign(:pending_delete_id, nil)}
  end

  def handle_event("start_edit_topic", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_topic, true)
     |> assign(:topic_form, to_form(Topic.changeset(socket.assigns.topic, %{})))}
  end

  def handle_event("cancel_edit_topic", _params, socket) do
    {:noreply, socket |> assign(:editing_topic, false) |> assign(:topic_form, nil)}
  end

  def handle_event("save_topic", %{"topic" => topic_params}, socket) do
    case Quiz.update_topic(socket.assigns.topic, topic_params) do
      {:ok, topic} ->
        {:noreply,
         socket
         |> assign(:topic, topic)
         |> assign(:page_title, topic.name)
         |> assign(:editing_topic, false)
         |> assign(:topic_form, nil)
         |> put_flash(:info, "Thema aktualisiert.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :topic_form, to_form(changeset, action: :update))}
    end
  end

  def handle_event("ask_delete_topic", _params, socket) do
    {:noreply, assign(socket, :confirm_action, :delete_topic)}
  end

  def handle_event("confirm_delete_topic", _params, socket) do
    {:ok, _} = Quiz.delete_topic(socket.assigns.topic)

    {:noreply,
     socket
     |> put_flash(:info, "Thema gelöscht.")
     |> push_navigate(to: ~p"/admin/topics")}
  end

  def handle_event("save", params, socket) do
    if uploads_pending?(socket) do
      {:noreply, put_flash(socket, :error, "Bild-Upload läuft noch – bitte kurz warten.")}
    else
      do_save(socket, params)
    end
  end

  def handle_event("validate", params, socket) do
    question_params = normalize_params(params)
    question = Map.get(socket.assigns, :question)
    changeset = build_changeset(question, question_params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:image, ref)
     |> assign(:preview_uploads, Map.delete(socket.assigns.preview_uploads, ref))}
  end

  # Duplicate preview URLs are ignored, but refs are unique per entry so it is safe.
  def handle_event("question_preview_upload", %{"ref" => ref, "url" => url}, socket) do
    previews = Map.put(socket.assigns.preview_uploads, ref, url)
    {:noreply, assign(socket, :preview_uploads, previews)}
  end

  def handle_event("remove_image", %{"index" => index}, socket) do
    index = String.to_integer(index)

    case socket.assigns[:question] do
      nil ->
        {:noreply, socket}

      q ->
        updated_q = %{q | images: List.delete_at(q.images || [], index)}
        changeset = Question.changeset(updated_q, %{})

        {:noreply,
         socket
         |> assign(:question, updated_q)
         |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("option_image_preview", %{"index" => index, "data_url" => data_url}, socket) do
    index = String.to_integer(index)
    previews = Map.put(socket.assigns.option_image_previews, index, data_url)
    {:noreply, assign(socket, :option_image_previews, previews)}
  end

  def handle_event("cancel_option_upload", %{"index" => index}, socket) do
    index = String.to_integer(index)
    upload_name = :"option_image_#{index}"

    socket =
      socket.assigns.uploads[upload_name].entries
      |> Enum.reduce(socket, fn entry, acc ->
        cancel_upload(acc, upload_name, entry.ref)
      end)

    previews = Map.drop(socket.assigns.option_image_previews, [index])
    {:noreply, assign(socket, :option_image_previews, previews)}
  end

  def handle_event("remove_option_image", %{"index" => index}, socket) do
    index = String.to_integer(index)

    case socket.assigns[:question] do
      nil ->
        {:noreply, socket}

      q ->
        new_options =
          q.options
          |> List.wrap()
          |> Enum.with_index()
          |> Enum.map(fn {opt, idx} ->
            if idx == index, do: Map.delete(opt, "image"), else: opt
          end)

        updated_q = %{q | options: new_options}
        changeset = Question.changeset(updated_q, %{})

        {:noreply,
         socket
         |> assign(:question, updated_q)
         |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("select_correct", %{"index" => index}, socket) do
    index = String.to_integer(index)
    form = socket.assigns.form
    current_opts = Phoenix.HTML.Form.input_value(form, :options) || []

    question_params = %{
      "correct_index" => index,
      "options" => current_opts,
      "prompt" => Phoenix.HTML.Form.input_value(form, :prompt),
      "status" => Phoenix.HTML.Form.input_value(form, :status),
      "image_position" => Phoenix.HTML.Form.input_value(form, :image_position),
      "layout" => Phoenix.HTML.Form.input_value(form, :layout)
    }

    question = Map.get(socket.assigns, :question)
    changeset = build_changeset(question, question_params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("view_image", %{"url" => url}, socket) do
    {:noreply, assign(socket, :viewing_image, url)}
  end

  def handle_event("close_image", _, socket) do
    {:noreply, assign(socket, :viewing_image, nil)}
  end

  defp do_save(socket, params) do
    question_params = normalize_params(params)

    new_images =
      consume_uploaded_entries(socket, :image, fn %{path: tmp_path}, _entry ->
        PubQuizzer.Uploads.store_compressed(tmp_path)
      end)

    existing_main_images =
      case socket.assigns[:question] do
        nil -> []
        q -> q.images || []
      end

    question_params = Map.put(question_params, "images", existing_main_images ++ new_images)

    new_option_images = consume_option_images(socket)
    existing_option_images = existing_option_images(socket)

    question_params =
      Map.update!(question_params, "options", fn options ->
        options
        |> Enum.with_index()
        |> Enum.map(fn {opt, idx} ->
          img = Map.get(new_option_images, idx) || Map.get(existing_option_images, idx)
          if img, do: Map.put(opt, "image", img), else: Map.delete(opt, "image")
        end)
      end)

    save_question(socket, question_params)
  end

  defp uploads_pending?(socket) do
    pending? = fn entries -> Enum.any?(entries, &(not &1.done?)) end

    pending?.(socket.assigns.uploads.image.entries) or
      Enum.any?(0..(@option_count - 1), fn i ->
        pending?.(socket.assigns.uploads[:"option_image_#{i}"].entries)
      end)
  end

  defp build_changeset(nil, params) do
    Question.changeset(
      %Question{options: @empty_options},
      Map.merge(%{"correct_index" => 0}, params)
    )
  end

  defp build_changeset(question, params) do
    Question.changeset(question, params)
  end

  defp normalize_params(%{"question" => q}), do: normalize_params(q)

  defp normalize_params(params) do
    params
    |> Map.update("options", [], &normalize_options/1)
    |> Map.update("correct_index", nil, fn
      nil -> nil
      "" -> nil
      v -> String.to_integer(v)
    end)
    |> normalize_status()
  end

  defp normalize_status(params) do
    case Map.pop(params, "published") do
      {nil, params} -> params
      {"true", params} -> Map.put(params, "status", "published")
      {_other, params} -> Map.put(params, "status", "draft")
    end
  end

  defp normalize_options(opts) when is_list(opts) do
    Enum.map(opts, fn
      %{"text" => _} = opt -> opt
      opt when is_binary(opt) -> %{"text" => opt}
    end)
  end

  defp normalize_options(opts) when is_map(opts) do
    opts
    |> Map.keys()
    |> Enum.filter(fn key -> key =~ ~r/^\d+$/ end)
    |> Enum.sort_by(&String.to_integer/1)
    |> Enum.map(fn key ->
      %{"text" => Map.get(opts, key, "")}
    end)
  end

  def live_option_upload(assigns, i) do
    assigns.uploads[:"option_image_#{i}"]
  end

  defp consume_option_images(socket) do
    for i <- 0..(@option_count - 1) do
      path =
        consume_uploaded_entries(socket, :"option_image_#{i}", fn %{path: tmp_path}, _entry ->
          PubQuizzer.Uploads.store_compressed(tmp_path)
        end)
        |> List.first()

      {i, path}
    end
    |> Map.new()
  end

  defp existing_option_images(socket) do
    case socket.assigns[:question] do
      nil ->
        %{}

      q ->
        q.options
        |> List.wrap()
        |> Enum.with_index()
        |> Enum.map(fn {opt, idx} -> {idx, Map.get(opt, "image")} end)
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Map.new()
    end
  end

  defp move_question(socket, _id, _delta) when socket.assigns.search != "", do: socket

  defp move_question(socket, id, delta) do
    topic_id = socket.assigns.topic.id
    ids = Quiz.list_question_ids_for_topic(topic_id)
    question_id = String.to_integer(id)
    index = Enum.find_index(ids, &(&1 == question_id))
    target = index && index + delta

    cond do
      is_nil(index) or target < 0 or target >= length(ids) ->
        socket

      true ->
        moved = Enum.at(ids, index)

        new_ids =
          ids
          |> List.replace_at(index, Enum.at(ids, target))
          |> List.replace_at(target, moved)

        case Quiz.reorder_questions(topic_id, new_ids) do
          {:ok, _questions} -> restream_questions(socket)
          {:error, :mismatch} -> restream_questions(socket)
        end
    end
  end

  defp restream_questions(socket) do
    questions =
      if socket.assigns.search == "" do
        Quiz.list_questions_for_topic(socket.assigns.topic.id)
      else
        Quiz.search_questions_for_topic(socket.assigns.topic.id, socket.assigns.search)
      end

    socket
    |> assign(:questions_count, length(questions))
    |> assign(:mini_questions, questions)
    |> assign(:first_question_id, questions |> List.first() |> then(&(&1 && &1.id)))
    |> assign(:last_question_id, questions |> List.last() |> then(&(&1 && &1.id)))
    |> stream(:questions, questions, reset: true)
  end

  defp compute_version_diffs(versions) do
    prevs = Enum.drop(versions, 1) ++ [nil]

    Enum.zip_with(versions, prevs, fn version, prev ->
      {version, diff_against(version, prev)}
    end)
  end

  defp diff_against(_current, nil), do: []

  defp diff_against(current, prev) do
    []
    |> maybe_diff(:prompt, current.prompt, prev.prompt)
    |> maybe_diff(:options, current.options, prev.options)
    |> maybe_diff(:correct_index, current.correct_index, prev.correct_index)
    |> maybe_diff(:images, version_images(current), version_images(prev))
    |> maybe_diff(:layout, current.layout, prev.layout)
    |> Enum.reverse()
  end

  # Old version rows only have `image`; new ones only `images`. Normalize both
  # to a list so the history diff stays meaningful across the migration.
  defp version_images(version) do
    case version.images do
      list when is_list(list) and list != [] -> list
      _ -> if version.image in [nil, ""], do: [], else: [version.image]
    end
  end

  defp maybe_diff(acc, _field, same, same), do: acc

  defp maybe_diff(acc, field, current_val, prev_val) do
    [%{field: field, old: prev_val, new: current_val} | acc]
  end

  defp save_question(socket, question_params) do
    question = Map.get(socket.assigns, :question)
    topic_id = socket.assigns.topic.id
    user = socket.assigns.current_scope.user

    {result, action} =
      case question do
        nil ->
          {Quiz.create_question(Map.put(question_params, "topic_id", topic_id)), :insert}

        q ->
          # Reload from the DB: in-memory edits (e.g. remove_image) would make
          # the changeset see "no change" for fields whose submitted value equals
          # the in-memory struct, silently skipping the DB write.
          {q.id |> Quiz.get_question!() |> Quiz.update_question(question_params), :update}
      end

    case result do
      {:ok, saved_question} ->
        version_action = if question, do: "updated", else: "created"
        record_version(saved_question, user, version_action)

        if question do
          {:noreply,
           socket
           |> put_flash(:info, "Frage aktualisiert.")
           |> load_editor(Quiz.get_question!(saved_question.id))
           |> restream_questions()}
        else
          {:noreply,
           socket
           |> assign(:preview_uploads, %{})
           |> put_flash(:info, "Frage erstellt.")
           |> push_navigate(to: ~p"/admin/topics/#{topic_id}/questions")}
        end

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form_submitted, true)
         |> assign(:form, to_form(changeset, action: action))}
    end
  end

  # The version row is best-effort history: the question is already persisted
  # at this point, so a version-insert failure must not turn a successful save
  # into a 500. Log and move on.
  defp record_version(question, user, action) do
    case Quiz.create_question_version(question, user, action) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning("failed to record question version: #{inspect(changeset.errors)}")
    end
  end
end
