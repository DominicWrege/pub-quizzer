defmodule PubQuizzerWeb.Admin.QuestionLive do
  use PubQuizzerWeb, :live_view

  require Logger

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Question
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

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:confirm_action, nil)
      |> assign(:pending_delete_id, nil)
      |> assign(:search, "")
      |> assign(:option_image_previews, %{})
      |> assign(:show_preview, false)
      |> assign(:viewing_image, nil)
      |> allow_upload(:image,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
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
    |> assign(:image_preview_url, nil)
    |> assign(:option_image_previews, %{})
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
    |> assign(:image_preview_url, nil)
    |> assign(:option_image_previews, %{})
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

  def handle_event("toggle_status", %{"id" => id}, socket) do
    question = Quiz.get_question!(String.to_integer(id))
    new_status = if question.status == "published", do: "draft", else: "published"
    {:ok, _} = Quiz.update_question(question, %{status: new_status})

    flash =
      if new_status == "published",
        do: "Frage veröffentlicht.",
        else: "Frage auf Entwurf gesetzt."

    {:noreply,
     socket
     |> restream_questions()
     |> put_flash(:info, flash)}
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:confirm_action, :delete_question)
     |> assign(:pending_delete_id, String.to_integer(id))}
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
     |> assign(:image_preview_url, nil)}
  end

  def handle_event("image_preview", %{"data_url" => data_url}, socket) do
    {:noreply, assign(socket, :image_preview_url, data_url)}
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
      "image_position" => Phoenix.HTML.Form.input_value(form, :image_position)
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

    question_params =
      consume_uploaded_entries(socket, :image, fn %{path: tmp_path}, _entry ->
        store_compressed(tmp_path)
      end)
      |> List.first()
      |> then(fn image_path ->
        if image_path, do: Map.put(question_params, "image", image_path), else: question_params
      end)

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
          store_compressed(tmp_path)
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

  defp store_compressed(tmp_path) do
    dir = PubQuizzer.upload_dir()
    File.mkdir_p!(dir)
    base = content_hash(tmp_path)

    if System.find_executable("ffmpeg") do
      filename = base <> ".jpg"
      dest = Path.join(dir, filename)
      thumb_dest = Path.join(dir, "thumb_" <> filename)
      compress_with_ffmpeg(tmp_path, dest, thumb_dest)
    else
      Logger.warning("ffmpeg not found, copying original file")
      filename = base <> source_extension(tmp_path)
      dest = Path.join(dir, filename)
      File.cp!(tmp_path, dest)
      {:ok, "/uploads/#{filename}"}
    end
  end

  # Names uploads by a SHA-256 hash of their content: collision-free, stable
  # across re-uploads, and safe to cache immutably (same bytes => same URL).
  defp content_hash(path) do
    path
    |> File.stream!([], 65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.url_encode64(padding: false)
  end

  defp source_extension(path) do
    case path |> Path.extname() |> String.downcase() do
      "" -> ".jpg"
      ext -> ext
    end
  end

  defp compress_with_ffmpeg(tmp_path, dest, thumb_dest) do
    filename = Path.basename(dest)

    args = [
      "-y",
      "-i",
      tmp_path,
      "-vf",
      "scale=w=1280:h=1280:force_original_aspect_ratio=decrease",
      "-q:v",
      "10",
      dest
    ]

    thumb_args = [
      "-y",
      "-i",
      tmp_path,
      "-vf",
      "scale=w=480:h=480:force_original_aspect_ratio=decrease",
      "-q:v",
      "15",
      thumb_dest
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        case System.cmd("ffmpeg", thumb_args, stderr_to_stdout: true) do
          {_thumb_output, 0} ->
            :ok

          {thumb_output, _} ->
            Logger.warning("thumbnail generation failed: #{thumb_output}")
        end

        {:ok, "/uploads/#{filename}"}

      {output, _exit_code} ->
        Logger.warning("ffmpeg compression failed, using original: #{output}")
        File.cp!(tmp_path, dest)
        {:ok, "/uploads/#{filename}"}
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
    |> maybe_diff(:image, current.image, prev.image)
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
          {Quiz.update_question(q, question_params), :update}
      end

    case result do
      {:ok, saved_question} ->
        version_action = if question, do: "updated", else: "created"
        Quiz.create_question_version!(saved_question, user, version_action)

        flash = if question, do: "Frage aktualisiert.", else: "Frage erstellt."

        {:noreply,
         socket
         |> assign(:image_preview_url, nil)
         |> put_flash(:info, flash)
         |> push_navigate(to: ~p"/admin/topics/#{topic_id}/questions")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form_submitted, true)
         |> assign(:form, to_form(changeset, action: action))}
    end
  end
end
