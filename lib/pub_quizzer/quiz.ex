defmodule PubQuizzer.Quiz do
  @moduledoc """
  The Quiz context: topics and questions management.
  """

  import Ecto.Query
  alias PubQuizzer.Repo
  alias PubQuizzer.Names
  alias PubQuizzer.Quiz.{Topic, Question, QuizEvent, Team, Round, Answer}

  @pubsub PubQuizzer.PubSub

  # --- Topics ---

  def list_topics do
    Topic
    |> order_by(asc: :name)
    |> preload(:questions)
    |> Repo.all()
  end

  def get_topic!(id) do
    Topic
    |> preload(:questions)
    |> Repo.get!(id)
  end

  def create_topic(attrs) do
    %Topic{}
    |> Topic.changeset(attrs)
    |> Repo.insert()
  end

  def update_topic(topic, attrs) do
    topic
    |> Topic.changeset(attrs)
    |> Repo.update()
  end

  def delete_topic(topic) do
    Repo.delete(topic)
  end

  def change_topic(topic, attrs \\ %{}) do
    Topic.changeset(topic, attrs)
  end

  # --- Questions ---

  def list_questions do
    Question
    |> order_by(asc: :position)
    |> preload(:topic)
    |> Repo.all()
  end

  def list_questions_for_topic(topic_id) do
    Question
    |> where(topic_id: ^topic_id)
    |> order_by(asc: :position)
    |> Repo.all()
  end

  def get_question!(id) do
    Question
    |> preload(:topic)
    |> Repo.get!(id)
  end

  def create_question(attrs) do
    topic_id = Map.get(attrs, "topic_id") || Map.get(attrs, :topic_id)

    %Question{}
    |> Question.changeset(Map.drop(attrs, ["topic_id", :topic_id]))
    |> Ecto.Changeset.put_change(:topic_id, topic_id)
    |> Repo.insert()
  end

  def update_question(question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(question) do
    Repo.delete(question)
  end

  def change_question(question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  # --- Quiz Events ---

  def list_events do
    QuizEvent
    |> order_by([e],
      asc:
        fragment(
          "CASE WHEN ? IN ('topic_selection','question','round_reveal') THEN 0 WHEN ? = 'lobby' THEN 1 WHEN ? = 'finished' THEN 2 ELSE 3 END",
          e.status,
          e.status,
          e.status
        ),
      desc: e.inserted_at
    )
    |> Repo.all()
  end

  def get_event!(id) do
    QuizEvent
    |> preload([:teams])
    |> Repo.get!(id)
  end

  def get_event_with_teams!(id) do
    teams_query = from t in Team, order_by: t.slot_index

    QuizEvent
    |> preload(teams: ^teams_query)
    |> Repo.get!(id)
  end

  def get_event_by_code(code) do
    teams_query = from t in Team, order_by: t.slot_index

    QuizEvent
    |> preload(teams: ^teams_query)
    |> Repo.get_by(code: code)
  end

  def create_event(attrs) do
    team_count = Map.get(attrs, "team_count") || Map.get(attrs, :team_count) || 6
    name = Map.get(attrs, "name") || Map.get(attrs, :name)
    code = generate_unique_code()

    Repo.transaction(fn ->
      event =
        %QuizEvent{}
        |> QuizEvent.changeset(%{code: code, name: name, team_count: team_count, status: "lobby"})
        |> Repo.insert!()

      names = Names.generate_many(team_count)

      Enum.with_index(names)
      |> Enum.each(fn {name, idx} ->
        %Team{}
        |> Team.changeset(%{name: name, slot_index: idx, quiz_event_id: event.id})
        |> Repo.insert!()
      end)

      get_event_with_teams!(event.id)
    end)
  end

  def start_event(event) do
    event
    |> QuizEvent.changeset(%{status: "topic_selection", started_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def stop_event(event) do
    event
    |> QuizEvent.changeset(%{status: "finished", finished_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def update_event(event, attrs) do
    event
    |> QuizEvent.changeset(attrs)
    |> Repo.update()
  end

  # --- Teams ---

  def list_teams_for_event(event_id) do
    Team
    |> where(quiz_event_id: ^event_id)
    |> order_by(asc: :slot_index)
    |> Repo.all()
  end

  def get_team!(id) do
    Team
    |> preload(:quiz_event)
    |> Repo.get!(id)
  end

  def update_team_name(team, name) do
    team
    |> Team.changeset(%{name: name})
    |> Repo.update()
  end

  def add_team_slot(event) do
    new_slot =
      list_teams_for_event(event.id)
      |> length()

    name = Names.generate(existing_team_names(event.id))

    {:ok, team} =
      %Team{}
      |> Team.changeset(%{name: name, slot_index: new_slot, quiz_event_id: event.id})
      |> Repo.insert()

    {:ok, updated} = update_event(event, %{team_count: event.team_count + 1})
    broadcast_team_update(event.id)
    {:ok, get_event_with_teams!(updated.id), team}
  end

  def remove_team_slot(event) do
    teams = list_teams_for_event(event.id)

    case List.last(teams) do
      nil ->
        {:error, :no_teams}

      team ->
        case team.claimed_at do
          nil ->
            {:ok, _} = Repo.delete(team)
            {:ok, updated} = update_event(event, %{team_count: event.team_count - 1})
            broadcast_team_update(event.id)
            {:ok, get_event_with_teams!(updated.id)}

          _ ->
            {:error, :team_claimed}
        end
    end
  end

  def delete_team(team) do
    Repo.transaction(fn ->
      event = get_event_with_teams!(team.quiz_event_id)
      Repo.delete!(team)
      update_event(event, %{team_count: event.team_count - 1})
    end)

    broadcast_team_update(team.quiz_event_id)
  end

  def delete_event(event) do
    Repo.transaction(fn ->
      event_id = event.id
      team_ids = from(t in Team, where: t.quiz_event_id == ^event_id, select: t.id) |> Repo.all()

      from(a in Answer, where: a.team_id in ^team_ids) |> Repo.delete_all()
      from(r in Round, where: r.quiz_event_id == ^event_id) |> Repo.delete_all()
      from(t in Team, where: t.quiz_event_id == ^event_id) |> Repo.delete_all()
      Repo.delete(event)
    end)
  end

  @doc """
  Claims the next free (unclaimed) team slot for an event.
  Returns {:ok, team} or {:error, :full}.
  """
  def claim_next_team_slot(event) do
    teams = list_teams_for_event(event.id)

    case Enum.find(teams, fn t -> t.claimed_at == nil end) do
      nil ->
        {:error, :full}

      team ->
        result =
          team
          |> Team.changeset(%{claimed_at: DateTime.utc_now()})
          |> Repo.update()

        broadcast_team_update(event.id)
        result
    end
  end

  @doc """
  Checks if a team belongs to a specific event.
  """
  def team_belongs_to_event?(team_id, event_id) do
    team = Repo.get(Team, team_id)
    team != nil and team.quiz_event_id == event_id
  end

  defp existing_team_names(event_id) do
    list_teams_for_event(event_id)
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  defp broadcast_team_update(event_id) do
    Phoenix.PubSub.broadcast(@pubsub, "quiz:event:#{event_id}", {:team_update, event_id})
  end

  defp generate_unique_code do
    code = generate_code()

    if Repo.get_by(QuizEvent, code: code) do
      generate_unique_code()
    else
      code
    end
  end

  defp generate_code do
    1..4
    |> Enum.map_join(fn _ -> Integer.to_string(:rand.uniform(10) - 1) end)
    |> String.pad_leading(4, "0")
  end

  # --- Rounds & Answers (for engine state recovery) ---

  def list_rounds_for_event(event_id) do
    Round
    |> where(quiz_event_id: ^event_id)
    |> order_by(asc: :round_number)
    |> Repo.all()
  end

  def list_answers_for_event(event_id) do
    Answer
    |> join(:inner, [a], r in Round, on: a.round_id == r.id)
    |> where([_, r], r.quiz_event_id == ^event_id)
    |> preload(:question)
    |> Repo.all()
  end

  def list_answers_for_round(round_id) do
    Answer
    |> where(round_id: ^round_id)
    |> preload(:question)
    |> Repo.all()
  end
end
