defmodule PubQuizzerWeb.QuizJoinController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  def join(conn, %{"code" => code}) do
    # Always claim a new team when submitting the join form,
    # even if the session already has a team for this event.
    # This ensures multiple browsers/tabs on the same machine
    # can each claim their own team.
    handle_join(conn, String.trim(code))
  end

  def join_with_code(conn, %{"code" => code}) do
    join(conn, %{"code" => code})
  end

  defp handle_join(conn, code) do
    case Quiz.get_event_by_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Kein Quiz mit diesem Code gefunden.")
        |> redirect(to: "/")

      event ->
        if event.status != "lobby" do
          conn
          |> put_flash(:error, "Dieses Quiz hat bereits begonnen.")
          |> redirect(to: "/")
        else
          maybe_reclaim_or_claim(conn, event)
        end
    end
  end

  defp maybe_reclaim_or_claim(conn, event) do
    existing_team_id = get_session(conn, :team_id)

    if existing_team_id && Quiz.team_belongs_to_event?(existing_team_id, event.id) do
      redirect(conn, to: "/quiz/#{event.code}/lobby")
    else
      case Quiz.claim_next_team_slot(event) do
        {:ok, team} ->
          # Register with the engine if it's already running
          Engine.register_team(event.id, team.id, team.name, team.slot_index)

          conn
          |> put_session(:team_id, team.id)
          |> put_session(:event_code, event.code)
          |> redirect(to: "/quiz/#{event.code}/lobby")

        {:error, :full} ->
          conn
          |> put_flash(:error, "Sorry, dieses Quiz ist voll.")
          |> redirect(to: "/")
      end
    end
  end
end
