defmodule PubQuizzerWeb.Admin.ResultLive do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    event = Quiz.get_event!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PubQuizzer.PubSub, "quiz:event:#{event.id}")
    end

    results = Quiz.get_event_results(id)

    {:ok,
     socket
     |> assign(:page_title, "Ergebnisse")
     |> assign(:event, event)
     |> assign(:results, results)}
  end

  @impl true
  def handle_info({:engine_state, _state}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:team_update, _event_id}, socket) do
    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    event = Quiz.get_event!(socket.assigns.event.id)
    results = Quiz.get_event_results(event.id)

    socket
    |> assign(:event, event)
    |> assign(:results, results)
  end

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
          <span>Ergebnisse</span>
          <%= if @event.status != "finished" do %>
            <span class="badge badge-sm badge-primary gap-1">
              <span class="size-1.5 rounded-full bg-current animate-pulse"></span> Live
            </span>
          <% end %>
          <span class="text-sm text-base-content/70 whitespace-nowrap">
            {@results.event.name || "Quiz"} · Code
            <span class="font-mono font-bold">{@results.event.code}</span>
          </span>
        </div>
        <:back>
          <.link
            navigate={~p"/admin/events"}
            class="btn btn-sm btn-soft"
          >
            <.icon name="hero-chevron-left" class="size-4" /> Zurück
          </.link>
        </:back>
      </.header>

      <%!-- Stats: timing + question difficulty --%>
      <%= if @results.rounds_data != [] do %>
        <div id="result-stats" class="mb-8">
          <div id="result-timing" class="stats border-2 border-base-300 bg-base-100">
            <%= if @results.timing.total_seconds do %>
              <div class="stat py-3 px-4">
                <div class="stat-title text-xs text-base-content/60">Dauer gesamt</div>
                <div class="stat-value text-lg">{format_duration(@results.timing.total_seconds)}</div>
              </div>
            <% end %>
            <div class="stat py-3 px-4">
              <div class="stat-title text-xs text-base-content/60">Reine Antwortzeit</div>
              <div class="stat-value text-lg">
                {format_duration(@results.timing.answering_seconds)}
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Final standings summary --%>
      <div class="mb-8">
        <h3 class="text-lg font-semibold mb-3">
          <.icon name="hero-trophy" class="size-5 inline text-warning" /> Gesamtwertung
        </h3>
        <div class="flex gap-3 flex-wrap">
          <div
            :for={{{id, name, score}, rank} <- Enum.with_index(@results.standings)}
            class={[
              "rounded-lg px-4 py-3 border-2",
              rank == 0 && "border-warning bg-warning/10",
              rank == 1 && "border-base-content/30 bg-base-200",
              rank == 2 && "border-amber-700/40 bg-amber-700/10",
              rank > 2 && "border-base-300 bg-base-200"
            ]}
          >
            <div class="flex items-center gap-3">
              <span class="text-xl font-bold text-base-content/50">{rank + 1}.</span>
              <span class="font-semibold">{name}</span>
              <span class="badge badge-primary">{score}</span>
            </div>
            <.team_quote id={id} accuracy={Map.get(@results.team_accuracy, id)} />
          </div>
        </div>
      </div>

      <%!-- Round-by-round spec comparison --%>
      <%= for {round_data, r_idx} <- Enum.with_index(@results.rounds_data) do %>
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-3">
            Runde {r_idx + 1}: {round_data.round.topic.name}
          </h3>

          <.round_stats
            round={round_data.round}
            questions={round_data.questions}
            question_stats={@results.question_stats}
            team_count={length(@results.teams)}
          />

          <div class="overflow-x-auto rounded-lg border-2 border-base-300">
            <table class="table table-sm">
              <thead>
                <tr class="border-b-2 border-base-300 bg-base-300">
                  <th class="min-w-[200px]">Frage</th>
                  <th :for={team <- @results.teams} class="text-center min-w-[80px]">
                    {team.name}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-300">
                <tr
                  :for={{question, q_idx} <- Enum.with_index(round_data.questions)}
                  class="bg-base-200"
                >
                  <td>
                    <div class="font-medium">
                      <span class="text-base-content/60 font-mono text-xs mr-1">Q{q_idx + 1}</span>
                      {question.prompt}
                    </div>
                    <div class="text-xs text-success mt-0.5">
                      Richtig: {String.upcase(letter(question.correct_index))}
                    </div>
                  </td>
                  <td :for={team <- @results.teams} class="text-center">
                    <% selected =
                      Map.get(@results.answer_lookup, {round_data.round.id, question.id, team.id}) %>
                    <%= if selected == nil do %>
                      <span class="text-base-content/50">—</span>
                    <% else %>
                      <% correct = selected == question.correct_index %>
                      <span class={[
                        "inline-flex items-center gap-1 px-2 py-1 rounded font-mono text-sm",
                        correct && "bg-success text-success-content",
                        !correct && "bg-error text-error-content"
                      ]}>
                        {String.upcase(letter(selected))}
                        <.icon
                          name={if correct, do: "hero-check-circle", else: "hero-x-circle"}
                          class="size-4"
                        />
                      </span>
                    <% end %>
                  </td>
                </tr>
                <tr class="border-t-2 border-base-300 bg-base-200 font-bold">
                  <td>Punkte</td>
                  <td :for={team <- @results.teams} class="text-center">
                    {round_score(@results.answer_lookup, round_data, team)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  attr :id, :any, required: true
  attr :accuracy, :any, default: nil

  defp team_quote(assigns) do
    ~H"""
    <div id={"team-quote-#{@id}"} class="mt-2">
      <%= case @accuracy do %>
        <% {_correct, 0} -> %>
          <div class="text-xs text-base-content/60">Quote: —</div>
        <% {correct, total} -> %>
          <% pct = round(correct / total * 100) %>
          <div class="text-xs text-base-content/60 mb-1">Quote: {pct} %</div>
          <div class="h-1.5 w-40 overflow-hidden rounded-full bg-base-300">
            <div class="h-full bg-primary" style={"width: #{pct}%"}></div>
          </div>
        <% nil -> %>
          <div class="text-xs text-base-content/60">Quote: —</div>
      <% end %>
    </div>
    """
  end

  attr :round, :map, required: true
  attr :questions, :list, required: true
  attr :question_stats, :map, required: true
  attr :team_count, :integer, required: true

  defp round_stats(assigns) do
    ~H"""
    <div
      id={"round-stats-#{@round.id}"}
      class="mb-4 rounded-lg border-2 border-base-300 bg-base-100 p-4"
    >
      <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h4 class="text-sm font-semibold">Antwortverteilung</h4>
        <div class="flex items-center gap-3 text-xs text-base-content/60">
          <span class="flex items-center gap-1">
            <span class="size-2.5 rounded-sm bg-success"></span> Richtige Option
          </span>
          <span class="flex items-center gap-1">
            <span class="size-2.5 rounded-sm bg-base-300"></span> Falsche Option
          </span>
          <span class="flex items-center gap-1">
            <span class="size-2.5 rounded-sm border border-base-300 bg-base-200"></span> Keine Antwort
          </span>
        </div>
      </div>
      <div class="space-y-3">
        <%= for {question, q_idx} <- Enum.with_index(@questions) do %>
          <% stats =
            Map.get(@question_stats, {@round.id, question.id}, %{
              picks: %{},
              no_answer: @team_count
            }) %>
          <% correct_count = Map.get(stats.picks, question.correct_index, 0) %>
          <div id={"question-stats-#{@round.id}-#{question.id}"}>
            <div class="mb-1 text-xs text-base-content/70">
              <span class="font-mono">Q{q_idx + 1}</span> {question.prompt} ·
              <span class="font-semibold text-success">{correct_count}/{@team_count} richtig</span>
            </div>
            <div class="flex h-7 w-full overflow-hidden rounded-md border border-base-300 bg-base-200">
              <%= for {idx, count} <- Enum.sort(stats.picks), count > 0 do %>
                <div
                  data-correct={to_string(idx == question.correct_index)}
                  class={[
                    "flex items-center justify-center overflow-hidden whitespace-nowrap text-xs font-semibold",
                    idx == question.correct_index && "bg-success text-success-content",
                    idx != question.correct_index && "bg-base-300 text-base-content/80"
                  ]}
                  style={"width: #{segment_pct(count, @team_count)}%"}
                  title={"#{letter(idx)}: #{count}×"}
                >
                  {letter(idx)} · {count}
                </div>
              <% end %>
              <%= if stats.no_answer > 0 do %>
                <div
                  data-no-answer
                  class="flex items-center justify-center overflow-hidden whitespace-nowrap bg-base-200 text-xs text-base-content/50"
                  style={"width: #{segment_pct(stats.no_answer, @team_count)}%"}
                  title={"Keine Antwort: #{stats.no_answer}×"}
                >
                  – · {stats.no_answer}
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp letter(index), do: letter_for_index(index)

  defp segment_pct(_count, 0), do: 0

  defp segment_pct(count, team_count) do
    Float.round(count / team_count * 100, 2)
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when seconds < 60, do: "#{seconds} Sek."

  defp format_duration(seconds) do
    minutes = round(seconds / 60)

    if minutes < 60 do
      "#{minutes} Min."
    else
      "#{div(minutes, 60)} Std. #{rem(minutes, 60)} Min."
    end
  end

  defp round_score(answer_lookup, round_data, team) do
    Enum.count(round_data.questions, fn question ->
      case Map.get(answer_lookup, {round_data.round.id, question.id, team.id}) do
        nil -> false
        selected -> selected == question.correct_index
      end
    end)
  end
end
