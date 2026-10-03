defmodule PubQuizzerWeb.QuizLive.Rejoin do
  use PubQuizzerWeb, :live_view

  alias PubQuizzer.Quiz

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Quiz.get_event_by_code(code) do
      nil ->
        {:ok, socket |> put_flash(:error, "Quiz nicht gefunden.") |> push_navigate(to: ~p"/")}

      event ->
        teams = Enum.filter(event.teams, & &1.claimed_at)

        {:ok,
         socket
         |> assign(event: event, page_title: "Team wieder beitreten", teams_empty?: teams == [])
         |> stream(:teams, teams)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      max_width="max-w-md"
      hide_nav_actions
      main_class="px-4 pt-6 pb-4 sm:pb-10 sm:px-6 lg:px-8"
    >
      <h1 class="text-xl font-bold mb-3">Team wieder beitreten</h1>
      <p class="text-sm mb-4">Wähle dein bestehendes Team, um weiterzuspielen.</p>
      <p :if={@teams_empty?} class="text-sm">
        Noch kein Team beigetreten. Bitte scanne deine Team-Karte.
      </p>
      <div id="rejoin-teams" phx-update="stream" class="flex flex-col gap-3">
        <.link
          :for={{dom_id, team} <- @streams.teams}
          id={dom_id}
          href={~p"/quiz/join/#{@event.code}/#{team.link_code}"}
          class="btn btn-soft h-auto min-h-12 py-3 px-4 whitespace-normal break-words"
        >
          {team.name}
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
