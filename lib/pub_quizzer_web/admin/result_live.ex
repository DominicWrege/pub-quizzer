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
      max_width="max-w-7xl"
      hide_nav_actions
    >
      <:nav_title>
        <span id="results-nav-title" class="block text-base font-semibold truncate">
          {if @event.status == "finished", do: "Ergebnisse", else: "Live-Werte"}
        </span>
      </:nav_title>
      <:nav_actions>
        <.link
          :if={@event.status != "lobby"}
          id="results-host-console"
          navigate={~p"/quiz/#{@event.code}/host"}
          class="btn btn-sm btn-soft min-h-[44px] gap-1 px-2"
        >
          <.icon name="hero-microphone" class="size-4 shrink-0" /> Moderator
        </.link>
        <.link
          :if={@event.status == "lobby"}
          id="results-quiz-overview"
          navigate={~p"/admin/events"}
          class="btn btn-sm btn-soft"
        >
          Quiz-Übersicht
        </.link>
      </:nav_actions>

      <p id="results-event-label" class="text-sm text-base-content/70">
        {@results.event.name || "Quiz"} · Code
        <span class="font-mono font-bold">{@results.event.code}</span>
      </p>

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
        <div id={"result-round-#{round_data.round.id}"} class="mb-8">
          <h3 class="text-lg font-semibold mb-3">
            Runde {r_idx + 1}: {round_data.round.topic.name}
          </h3>

          <div class="overflow-x-auto rounded-lg border-2 border-base-content/30">
            <table class="table text-base text-base-content">
              <thead>
                <tr class="border-b-2 border-base-300 bg-base-300">
                  <th scope="col" class="min-w-[140px] px-4 py-3 text-base text-base-content">
                    Frage
                  </th>
                  <th
                    :for={team <- @results.teams}
                    scope="col"
                    class="text-center min-w-[80px] px-4 py-3 text-base text-base-content"
                  >
                    {team.name}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-300">
                <tr
                  :for={{question, q_idx} <- Enum.with_index(round_data.questions)}
                  class="bg-base-200"
                >
                  <td class="px-4 py-3">
                    <span
                      id={"result-question-#{round_data.round.id}-#{question.id}"}
                      data-test="result-question-label"
                      class="block text-lg font-semibold text-base-content whitespace-nowrap"
                    >
                      Frage {q_idx + 1}
                    </span>
                    <div class="text-sm font-medium text-base-content mt-1">
                      Richtig: {String.upcase(letter(question.correct_index))}
                    </div>
                  </td>
                  <td :for={team <- @results.teams} class="text-center px-4 py-3">
                    <% selected =
                      Map.get(@results.answer_lookup, {round_data.round.id, question.id, team.id}) %>
                    <%= if selected == nil do %>
                      <span class="text-base-content font-mono text-lg">—</span>
                    <% else %>
                      <% correct = selected == question.correct_index %>
                      <span class={[
                        "inline-flex items-center gap-1.5 px-3 py-1.5 rounded font-mono text-base font-bold",
                        correct && "bg-success text-success-content",
                        !correct && "bg-error text-error-content"
                      ]}>
                        {String.upcase(letter(selected))}
                        <.icon
                          name={if correct, do: "hero-check-circle", else: "hero-x-circle"}
                          class="size-5"
                        />
                      </span>
                    <% end %>
                  </td>
                </tr>
                <tr class="border-t-2 border-base-300 bg-base-200 font-bold">
                  <td class="px-4 py-3">Punkte</td>
                  <td :for={team <- @results.teams} class="text-center px-4 py-3">
                    {round_score(@results.answer_lookup, round_data, team)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

      <%= if @results.rounds_data != [] do %>
        <div id="result-stats" class="mt-8 border-t border-base-300 pt-4 text-sm text-base-content">
          <span id="result-timing">
            <%= if @results.timing.total_seconds do %>
              Dauer gesamt {format_duration(@results.timing.total_seconds)} ·
            <% end %>
            Reine Antwortzeit {format_duration(@results.timing.answering_seconds)}
          </span>
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

  defp letter(index), do: letter_for_index(index)

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
