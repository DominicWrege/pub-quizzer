defmodule PubQuizzerWeb.QuizJoinController do
  use PubQuizzerWeb, :controller

  alias PubQuizzer.Quiz
  alias PubQuizzer.Quiz.Engine

  def join(conn, %{"code" => code}) do
    handle_join(conn, String.trim(code))
  end

  def join_with_code(conn, %{"code" => code}) do
    join(conn, %{"code" => code})
  end

  def join_with_code_and_slot(conn, %{"code" => code, "slot" => slot}) do
    case Integer.parse(slot) do
      {slot_num, ""} when slot_num >= 1 ->
        handle_join_with_slot(conn, String.trim(code), slot_num - 1)

      _ ->
        handle_join_with_team_code(conn, String.trim(code), String.downcase(slot))
    end
  end

  defp handle_join_with_team_code(conn, code, team_code) do
    case Quiz.get_event_by_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Kein Quiz mit diesem Code gefunden.")
        |> redirect(to: "/")

      event ->
        case Enum.find(event.teams, &(&1.link_code == team_code)) do
          nil ->
            conn
            |> put_flash(:error, "Ungültiger Team-Link.")
            |> redirect(to: "/")

          team ->
            handle_join_with_slot(conn, code, team.slot_index)
        end
    end
  end

  defp handle_join_with_slot(conn, code, slot_index) do
    case Quiz.get_event_by_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Kein Quiz mit diesem Code gefunden.")
        |> redirect(to: "/")

      event ->
        case Quiz.claim_team_slot(event, slot_index) do
          {:ok, team} ->
            join_as_team(conn, event, team)

          {:error, :quiz_started} ->
            reject_new_team(conn, event)

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Dieser Team-Link ist ungültig.")
            |> redirect(to: "/")
        end
    end
  end

  defp handle_join(conn, code) do
    case Quiz.get_event_by_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Kein Quiz mit diesem Code gefunden.")
        |> redirect(to: "/")

      event ->
        maybe_reclaim_or_claim(conn, event)
    end
  end

  defp maybe_reclaim_or_claim(conn, event) do
    existing_team_id = get_session(conn, :team_id)
    existing_team = Enum.find(event.teams, &(&1.id == existing_team_id && &1.claimed_at))

    cond do
      existing_team ->
        join_as_team(conn, event, existing_team)

      event.status != "lobby" ->
        reject_new_team(conn, event)

      true ->
        case Quiz.claim_next_team_slot(event) do
          {:ok, team} ->
            join_as_team(conn, event, team)

          {:error, :quiz_started} ->
            reject_new_team(conn, event)

          {:error, :full} ->
            conn
            |> put_flash(:error, "Sorry, dieses Quiz ist voll.")
            |> redirect(to: "/")
        end
    end
  end

  defp join_as_team(conn, event, team) do
    Engine.register_team(event.id, team.id, team.name, team.slot_index)

    conn
    |> put_session(:team_id, team.id)
    |> put_session(:event_code, event.code)
    |> redirect(to: ~p"/quiz/#{event.code}/lobby/#{team.link_code}")
  end

  defp reject_new_team(conn, event) do
    render(conn, :blocked, event: event)
  end
end
