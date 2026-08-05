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
      :index -> index(assigns)
      :new -> new(assigns)
      :edit -> edit(assigns)
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
        <%= for {msg, _} <- @form.errors do %>
          <span>{msg}</span>
        <% end %>
        <%= for {msg, _} <- @form[:prompt].errors do %>
          <span>{msg}</span>
        <% end %>
        <%= for {msg, _} <- @form[:options].errors do %>
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
          <% current = @form[:layout].value || "classic" %>

          <.layout_thumb current={current} value="classic" label="Text">
            <div class="h-1.5 w-full rounded-sm bg-current opacity-70"></div>
            <div class="mt-1 space-y-0.5">
              <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
              <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
              <div class="h-1 w-full rounded-sm bg-current opacity-30"></div>
            </div>
          </.layout_thumb>

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

      <%= if (@form[:layout].value || "classic") == "image_side" do %>
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

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:confirm_action, nil)
      |> assign(:pending_delete_id, nil)
      |> assign(:search, "")
      |> assign(:option_image_previews, %{})
      |> assign(:preview_uploads, %{})
      |> assign(:show_preview, false)
      |> assign(:viewing_image, nil)
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
    questions = Quiz.list_questions_for_topic(topic.id)

    socket
    |> assign(:topic, topic)
    |> assign(:page_title, topic.name)
    |> assign(:questions_count, length(questions))
    |> assign(:editing_topic, false)
    |> assign(:topic_form, nil)
    |> assign(:first_question_id, questions |> List.first() |> then(&(&1 && &1.id)))
    |> assign(:last_question_id, questions |> List.last() |> then(&(&1 && &1.id)))
    |> stream(:questions, questions)
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
    changeset = Question.changeset(question, %{})
    versions = Quiz.list_question_versions(question.id)

    socket
    |> assign(:topic, topic)
    |> assign(:question, question)
    |> assign(:page_title, "Frage bearbeiten – #{topic.name}")
    |> assign(:form, to_form(changeset))
    |> assign(:form_submitted, false)
    |> assign(:option_image_previews, %{})
    |> assign(:preview_uploads, %{})
    |> assign(:show_preview, false)
    |> assign(:versions, compute_version_diffs(versions))
  end

  @impl true
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
      ordered_ids = Enum.map(ids, &String.to_integer/1)

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

    {:noreply,
     socket
     |> assign(:confirm_action, nil)
     |> assign(:pending_delete_id, nil)
     |> restream_questions()
     |> put_flash(:info, "Frage gelöscht.")}
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

    existing_images =
      case socket.assigns[:question] do
        nil -> []
        q -> q.images || []
      end

    question_params = Map.put(question_params, "images", existing_images ++ new_images)

    option_images = consume_option_images(socket)
    existing_images = existing_option_images(socket)

    question_params =
      Map.update!(question_params, "options", fn options ->
        options
        |> Enum.with_index()
        |> Enum.map(fn {opt, idx} ->
          img = Map.get(option_images, idx) || Map.get(existing_images, idx)
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
    acc ++ [%{field: field, old: prev_val, new: current_val}]
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

        flash = if question, do: "Frage aktualisiert.", else: "Frage erstellt."

        {:noreply,
         socket
         |> assign(:preview_uploads, %{})
         |> put_flash(:info, flash)
         |> push_navigate(to: ~p"/admin/topics/#{topic_id}/questions")}

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
