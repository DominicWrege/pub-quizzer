defmodule PubQuizzerWeb.Admin.ImportLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Import

  embed_templates "import_live/*"

  @max_file_size 5_000_000

  @impl true
  def render(assigns) do
    index(assigns)
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope[:user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Bitte melde dich an.")
         |> redirect(to: "/admin/login")}

      user.role != "superadmin" ->
        {:ok,
         socket
         |> put_flash(:error, "Keine Berechtigung für diesen Bereich.")
         |> redirect(to: "/admin/topics")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Fragenkatalog importieren")
         |> assign(:result, nil)
         |> assign(:file_error, nil)
         |> assign(:imported, nil)
         |> allow_upload(:catalog,
           accept: ~w(.json),
           max_entries: 1,
           max_file_size: @max_file_size
         )}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket |> assign(:file_error, nil) |> assign(:result, nil)}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> clear_catalog_uploads()
     |> assign(:file_error, nil)
     |> assign(:result, nil)
     |> assign(:imported, nil)}
  end

  def handle_event("preview", _params, socket) do
    case read_upload(socket) do
      {:ok, json} ->
        existing = Quiz.list_all_topic_names()

        case Import.parse_and_validate(json, existing) do
          {:ok, result} ->
            {:noreply,
             socket
             |> assign(:result, result)
             |> assign(:file_error, nil)
             |> assign(:imported, nil)}

          {:error, errors} ->
            {:noreply,
             socket
             |> assign(:file_error, Enum.join(errors, " "))
             |> assign(:result, nil)}
        end

      {:error, message} ->
        {:noreply, socket |> assign(:file_error, message) |> assign(:result, nil)}
    end
  end

  def handle_event("toggle_question_status", %{"topic" => topic, "question" => question}, socket) do
    with %{importable: importable} = result <- socket.assigns.result,
         {topic_index, ""} <- Integer.parse(topic),
         {question_index, ""} <- Integer.parse(question),
         %{questions: questions} when topic_index >= 0 and question_index >= 0 <-
           Enum.at(importable, topic_index),
         question when not is_nil(question) <- Enum.at(questions, question_index) do
      status = if question["status"] == "published", do: "draft", else: "published"

      importable =
        List.update_at(importable, topic_index, fn topic ->
          Map.update!(topic, :questions, fn questions ->
            List.update_at(questions, question_index, &Map.put(&1, "status", status))
          end)
        end)

      {:noreply, assign(socket, :result, %{result | importable: importable})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("publish_all", _params, socket) do
    case socket.assigns.result do
      %{importable: importable} = result ->
        importable =
          Enum.map(importable, fn topic ->
            Map.update!(topic, :questions, fn questions ->
              Enum.map(questions, &Map.put(&1, "status", "published"))
            end)
          end)

        {:noreply, assign(socket, :result, %{result | importable: importable})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_import", _params, socket) do
    case socket.assigns.result do
      %{importable: [_ | _] = importable} ->
        case Import.import(importable) do
          {:ok, summary} ->
            {:noreply,
             socket
             |> assign(:imported, summary)
             |> assign(:result, nil)
             |> assign(:file_error, nil)
             |> clear_catalog_uploads()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import fehlgeschlagen: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Keine importierbaren Themen vorhanden.")}
    end
  end

  @doc "Renders the validation preview (importable topics, warnings, skipped entries)."
  attr :result, :map, required: true

  def import_preview(assigns) do
    ~H"""
    <div class="mt-6 space-y-6">
      <div class="flex flex-wrap items-center gap-2">
        <span class="badge badge-success">{length(@result.importable)} importierbar</span>
        <span class="badge badge-ghost">{length(@result.skipped)} übersprungen</span>
        <span class="badge badge-warning">{length(@result.warnings)} Hinweis(e)</span>
      </div>

      <%= if @result.warnings != [] do %>
        <div class="alert alert-warning items-start">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <div>
            <p class="font-semibold">Hinweise</p>
            <ul class="mt-1 list-disc list-inside text-sm">
              <li :for={warning <- @result.warnings}>
                {warning.topic} · {warning.question}: {warning.message}
              </li>
            </ul>
          </div>
        </div>
      <% end %>

      <%= if @result.skipped != [] do %>
        <div class="rounded-xl border-2 border-base-300">
          <div class="border-b-2 border-base-300 bg-base-200 px-4 py-2 text-sm font-semibold">
            Übersprungene Themen
          </div>
          <ul class="divide-y divide-base-300">
            <li
              :for={skipped <- @result.skipped}
              class="flex flex-col gap-0.5 px-4 py-3 text-sm sm:flex-row sm:gap-2"
            >
              <span class="font-medium">{skipped.name}</span>
              <span class="text-base-content/70">{skipped.reason}</span>
            </li>
          </ul>
        </div>
      <% end %>

      <%= if @result.importable != [] do %>
        <div class="space-y-3">
          <div
            :for={{topic, topic_index} <- Enum.with_index(@result.importable)}
            class="rounded-xl border-2 border-base-300"
          >
            <details open>
              <summary class="flex cursor-pointer items-center justify-between gap-2 bg-base-200 px-4 py-3">
                <span class="font-semibold">{topic.name}</span>
                <span class="badge badge-sm">{length(topic.questions)} Frage(n)</span>
              </summary>
              <ol class="divide-y divide-base-300">
                <li
                  :for={{question, index} <- Enum.with_index(topic.questions, 1)}
                  class="flex items-center justify-between gap-3 px-4 py-3 text-sm"
                >
                  <div class="flex gap-2">
                    <span class="shrink-0 font-mono text-base-content/50">{index}.</span>
                    <div>
                      <p class="whitespace-pre-line">{question["prompt"]}</p>
                      <p class="mt-1 text-xs text-base-content/60">
                        Richtige Antwort:
                        <span class="font-mono font-bold text-success">
                          {letter_for(question["correct_index"])}
                        </span>
                      </p>
                    </div>
                  </div>
                  <div class={[
                    "rounded-xl border px-3 py-2 transition-colors shrink-0",
                    if(question["status"] == "published",
                      do: "border-success/40 bg-success/10",
                      else: "border-warning/40 bg-warning/10"
                    )
                  ]}>
                    <div class="flex items-center gap-2">
                      <div class={[
                        "size-8 rounded-lg grid place-items-center shrink-0 transition-colors",
                        if(question["status"] == "published",
                          do: "bg-success/20 text-success",
                          else: "bg-warning/20 text-warning"
                        )
                      ]}>
                        <.icon
                          name={
                            if question["status"] == "published",
                              do: "hero-check-circle",
                              else: "hero-pencil"
                          }
                          class="size-4"
                        />
                      </div>
                      <span class="text-xs font-semibold">
                        {if question["status"] == "published", do: "Veröffentlicht", else: "Entwurf"}
                      </span>
                      <input
                        id={"import-question-publish-#{topic_index}-#{index - 1}"}
                        type="checkbox"
                        phx-click="toggle_question_status"
                        phx-value-topic={topic_index}
                        phx-value-question={index - 1}
                        aria-label={"Status für Frage #{index}"}
                        checked={question["status"] == "published"}
                        class="toggle toggle-success toggle-sm"
                      />
                    </div>
                  </div>
                </li>
              </ol>
            </details>
          </div>
        </div>

        <div class="flex flex-wrap justify-between gap-2">
          <button type="button" phx-click="publish_all" class="btn">
            <.icon name="hero-eye" class="size-4" /> Alle Fragen veröffentlichen
          </button>
          <button phx-click="confirm_import" class="btn btn-primary">
            <.icon name="hero-arrow-down-tray" class="size-4" />
            {length(@result.importable)} Thema(en) importieren
          </button>
        </div>
      <% else %>
        <div class="alert alert-info">
          <.icon name="hero-information-circle" class="size-5 shrink-0" />
          <span>Keine neuen Themen zum Importieren gefunden.</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp read_upload(socket) do
    case uploaded_entries(socket, :catalog) do
      {[entry], []} ->
        case consume_uploaded_entry(socket, entry, fn %{path: path} ->
               {:ok, File.read!(path)}
             end) do
          json when is_binary(json) -> {:ok, json}
          _ -> {:error, "Die Datei konnte nicht gelesen werden."}
        end

      {[], []} ->
        {:error, "Bitte zuerst eine JSON-Datei auswählen."}

      {_entries, errors} ->
        {:error, upload_error_message(errors)}
    end
  end

  defp clear_catalog_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.catalog.entries, socket, fn entry, acc ->
      cancel_upload(acc, :catalog, entry.ref)
    end)
  end

  defp upload_error_message(errors) do
    errors
    |> Enum.map(fn
      :too_large -> "Datei ist zu groß (max. 5 MB)."
      :not_accepted -> "Nur .json-Dateien werden akzeptiert."
      :too_many_files -> "Es kann nur eine Datei hochgeladen werden."
      other -> "Upload-Fehler: #{inspect(other)}"
    end)
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  @doc "Human-readable label for a LiveView upload error."
  def upload_error_label(:too_large), do: "zu groß"
  def upload_error_label(:not_accepted), do: "falscher Dateityp"
  def upload_error_label(:too_many_files), do: "zu viele Dateien"
  def upload_error_label(other), do: inspect(other)

  defp letter_for(index) when is_integer(index), do: Enum.at(~w(A B C D E F), index)
  defp letter_for(_index), do: "?"
end
