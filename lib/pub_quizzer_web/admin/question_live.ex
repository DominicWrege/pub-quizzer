defmodule PubQuizzerWeb.Admin.QuestionLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Question
  embed_templates "question_live/*"

  @upload_dir "priv/static/uploads"
  @option_count 4

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :index -> index(assigns)
      :new -> new(assigns)
      :edit -> edit(assigns)
    end
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
      |> allow_upload(:image,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 20_000_000
      )

    socket =
      Enum.reduce(0..(@option_count - 1), socket, fn i, acc ->
        allow_upload(acc, :"option_image_#{i}",
          accept: ~w(.jpg .jpeg .png .gif .webp),
          max_entries: 1,
          max_file_size: 20_000_000
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

    socket
    |> assign(:topic, topic)
    |> assign(:page_title, "Fragen")
    |> stream(:questions, Quiz.list_questions_for_topic(topic.id))
  end

  defp apply_action(socket, :new, %{"topic_id" => topic_id}) do
    topic = Quiz.get_topic!(topic_id)
    empty_opts = [%{"text" => ""}, %{"text" => ""}, %{"text" => ""}, %{"text" => ""}]
    changeset = Question.changeset(%Question{options: empty_opts}, %{correct_index: 0})

    socket
    |> assign(:topic, topic)
    |> assign(:question, nil)
    |> assign(:page_title, "Neue Frage")
    |> assign(:form, to_form(changeset))
    |> assign(:form_submitted, false)
    |> assign(:image_preview_url, nil)
    |> assign(:option_image_previews, %{})
    |> assign(:show_preview, false)
    |> assign_option_uploads()
  end

  defp apply_action(socket, :edit, %{"topic_id" => topic_id, "id" => id}) do
    topic = Quiz.get_topic!(topic_id)
    question = Quiz.get_question!(id)
    changeset = Question.changeset(question, %{})
    versions = Quiz.list_question_versions(question.id)

    socket
    |> assign(:topic, topic)
    |> assign(:question, question)
    |> assign(:page_title, "Frage bearbeiten")
    |> assign(:form, to_form(changeset))
    |> assign(:form_submitted, false)
    |> assign(:image_preview_url, nil)
    |> assign(:option_image_previews, %{})
    |> assign(:show_preview, false)
    |> assign(:versions, compute_version_diffs(versions))
    |> assign_option_uploads()
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
     |> stream(:questions, questions, reset: true)}
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

  def handle_event("validate", params, socket) do
    question_params = normalize_params(params)

    question = Map.get(socket.assigns, :question)

    empty_opts = [%{"text" => ""}, %{"text" => ""}, %{"text" => ""}, %{"text" => ""}]

    changeset =
      case question do
        nil -> Question.changeset(%Question{options: empty_opts}, Map.merge(%{"correct_index" => 0}, question_params))
        _ -> Question.changeset(question, question_params)
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    socket =
      if ref do
        cancel_upload(socket, :image, ref)
      else
        socket
      end

    {:noreply, assign(socket, :image_preview_url, nil)}
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
      "prompt" => Phoenix.HTML.Form.input_value(form, :prompt)
    }

    question = Map.get(socket.assigns, :question)
    empty_opts = [%{"text" => ""}, %{"text" => ""}, %{"text" => ""}, %{"text" => ""}]

    changeset =
      case question do
        nil -> Question.changeset(%Question{options: empty_opts}, question_params)
        _ -> Question.changeset(question, question_params)
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  defp normalize_params(%{"question" => q}) do
    q
    |> Map.update("options", [], fn opts ->
      normalize_options(opts)
    end)
    |> Map.update("correct_index", nil, fn
      nil -> nil
      "" -> nil
      v -> String.to_integer(v)
    end)
  end

  defp normalize_params(%{"prompt" => _, "options" => _} = params) do
    params
    |> Map.update("options", [], fn opts -> normalize_options(opts) end)
    |> Map.update("correct_index", nil, fn
      nil -> nil
      "" -> nil
      v -> String.to_integer(v)
    end)
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

  defp assign_option_uploads(socket) do
    assign(
      socket,
      :option_uploads,
      for i <- 0..(@option_count - 1), into: %{} do
        {i, socket.assigns.uploads[:"option_image_#{i}"]}
      end
    )
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
    filename = "#{System.unique_integer([:positive, :monotonic])}.jpg"
    dest = Path.join(@upload_dir, filename)
    thumb_dest = Path.join(@upload_dir, "thumb_#{filename}")
    File.mkdir_p!(@upload_dir)

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
        # Thumbnail is best-effort — not worth failing the upload if it can't be made.
        case System.cmd("ffmpeg", thumb_args, stderr_to_stdout: true) do
          {_thumb_output, 0} ->
            :ok

          {thumb_output, _} ->
            require Logger
            Logger.warning("thumbnail generation failed: #{thumb_output}")
        end

        {:ok, "/uploads/#{filename}"}

      {output, _exit_code} ->
        # Reject large files rather than serving uncompressed originals
        {:ok, size} = File.stat(tmp_path)

        if size > 1_000_000 do
          {:error, "image compression failed and original is too large: #{output}"}
        else
          require Logger
          Logger.warning("ffmpeg compression failed, using original: #{output}")
          File.cp!(tmp_path, dest)
          {:ok, "/uploads/#{filename}"}
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

    stream(socket, :questions, questions, reset: true)
  end

  defp compute_version_diffs(versions) do
    versions
    |> Enum.with_index()
    |> Enum.map(fn {version, idx} ->
      prev = Enum.at(versions, idx + 1)
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
          {Quiz.update_question(q, question_params), :insert}
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
