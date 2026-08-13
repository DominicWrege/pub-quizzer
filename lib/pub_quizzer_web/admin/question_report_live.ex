defmodule PubQuizzerWeb.Admin.QuestionReportLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  @impl true
  def mount(_params, _session, socket) do
    entries = Quiz.get_question_report()

    topics =
      entries
      |> Enum.map(&{&1.topic_id, &1.topic_name})
      |> Enum.uniq()
      |> Enum.sort_by(&elem(&1, 1))

    {:ok,
     socket
     |> assign(:page_title, "Fragen-Bericht")
     |> assign(:entries, entries)
     |> assign(:topics, topics)
     |> assign(:topic_filter, "")
     |> assign(:sort, "hardest")
     |> assign_rows(entries, "", "hardest")}
  end

  @impl true
  def handle_event("filter", params, socket) do
    topic_filter = Map.get(params, "topic_id", "")
    sort = Map.get(params, "sort", "hardest")

    {:noreply,
     socket
     |> assign(:topic_filter, topic_filter)
     |> assign(:sort, sort)
     |> assign_rows(socket.assigns.entries, topic_filter, sort)}
  end

  defp assign_rows(socket, entries, topic_filter, sort) do
    rows =
      entries
      |> Enum.filter(fn entry ->
        topic_filter == "" or to_string(entry.topic_id) == topic_filter
      end)
      |> sort_entries(sort)

    assign(socket, :rows, rows)
  end

  defp sort_entries(entries, "asked"),
    do: Enum.sort_by(entries, fn e -> {-e.asked_in, e.pct} end)

  defp sort_entries(entries, _hardest), do: Enum.sort_by(entries, & &1.pct)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      max_width="max-w-7xl"
    >
      <.header>
        <div class="flex items-baseline gap-2 sm:gap-3 flex-wrap">
          <span>Fragen-Bericht</span>
          <span class="text-sm text-base-content/70 whitespace-nowrap">
            {length(@entries)} Fragen aus allen abgeschlossenen Quiz
          </span>
        </div>
        <:back>
          <.link navigate={~p"/admin/events"} class="btn btn-sm btn-soft">
            <.icon name="hero-chevron-left" class="size-4" /> Zurück
          </.link>
        </:back>
      </.header>

      <div id="question-report-filters" class="mb-4">
        <form phx-change="filter" id="question-report-filter-form" class="flex flex-wrap gap-2">
          <select name="topic_id" class="select select-sm select-bordered">
            <option value="" selected={@topic_filter == ""}>Alle Themen</option>
            <option
              :for={{id, name} <- @topics}
              value={id}
              selected={@topic_filter == to_string(id)}
            >
              {name}
            </option>
          </select>
          <select name="sort" class="select select-sm select-bordered">
            <option value="hardest" selected={@sort == "hardest"}>Schwerste zuerst</option>
            <option value="asked" selected={@sort == "asked"}>Häufigste zuerst</option>
          </select>
        </form>
      </div>

      <div class="overflow-x-auto rounded-lg border-2 border-base-300">
        <table class="table table-sm">
          <thead>
            <tr class="border-b-2 border-base-300 bg-base-300">
              <th class="px-4 py-3">Frage</th>
              <th class="px-4 py-3 text-center">Gefragt</th>
              <th class="px-4 py-3 text-center">Antworten</th>
              <th class="px-4 py-3 text-center">Richtig</th>
              <th class="px-4 py-3 min-w-[200px]">Verteilung</th>
              <th class="px-4 py-3">Falle</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr :if={@rows == []} id="question-report-empty" class="bg-base-200">
              <td colspan="6" class="px-4 py-6 text-center text-base-content/70">
                Keine Fragen aus abgeschlossenen Quiz gefunden.
              </td>
            </tr>
            <tr
              :for={entry <- @rows}
              id={"question-report-#{entry.question.id}"}
              class="bg-base-200 hover:bg-base-300/60"
            >
              <td class="px-4 py-3">
                <div class="font-medium">{entry.question.prompt}</div>
                <div class="text-xs text-base-content/60">{entry.topic_name}</div>
              </td>
              <td class="px-4 py-3 text-center font-mono">{entry.asked_in}×</td>
              <td class="px-4 py-3 text-center font-mono">{entry.answers}</td>
              <td class="px-4 py-3 text-center">
                <span class={[
                  "font-mono font-bold",
                  entry.pct < 40 && "text-error",
                  (entry.pct >= 40 and entry.pct < 70) && "text-base-content/70",
                  entry.pct >= 70 && "text-success"
                ]}>
                  {entry.pct} %
                </span>
              </td>
              <td class="px-4 py-3">
                <div class="flex h-6 w-full overflow-hidden rounded-md border border-base-300 bg-base-200">
                  <%= for {idx, count} <- Enum.sort(entry.picks), count > 0 do %>
                    <div
                      data-correct={to_string(idx == entry.question.correct_index)}
                      class={[
                        "flex items-center justify-center overflow-hidden whitespace-nowrap text-xs font-semibold",
                        idx == entry.question.correct_index && "bg-success text-success-content",
                        idx != entry.question.correct_index && "bg-base-300 text-base-content/80"
                      ]}
                      style={"width: #{segment_pct(count, entry.answers)}%"}
                      title={"#{letter_for_index(idx)}: #{count}×"}
                    >
                      {letter_for_index(idx)} · {count}
                    </div>
                  <% end %>
                </div>
              </td>
              <td class="px-4 py-3 text-sm">
                <%= if entry.trap do %>
                  <% {idx, count} = entry.trap %>
                  <span class="font-mono font-bold">{letter_for_index(idx)}</span>
                  <span class="text-base-content/60">· {count}×</span>
                <% else %>
                  <span class="text-base-content/50">—</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp segment_pct(_count, 0), do: 0

  defp segment_pct(count, total) do
    Float.round(count / total * 100, 2)
  end
end
