defmodule PubQuizzer.Quiz do
  @moduledoc """
  The Quiz context: topics and questions management.
  """

  import Ecto.Query
  alias PubQuizzer.Repo
  alias PubQuizzer.Names
  alias PubQuizzer.Quiz.{Topic, Question, QuestionVersion, QuizEvent, Team, Round, Answer}

  @pubsub PubQuizzer.PubSub

  # --- Topics ---

  def list_topics do
    Topic
    |> order_by(asc: :name)
    |> preload(:questions)
    |> Repo.all()
  end

  @doc """
  Returns all topics as lightweight `%{id, name}` maps, without preloading questions.
  Used by the engine to build available_topics lists.
  """
  def list_topic_names do
    Topic
    |> order_by(asc: :name)
    |> select([t], %{id: t.id, name: t.name})
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
    |> attach_last_editor()
  end

  def search_questions_for_topic(topic_id, query) when is_binary(query) do
    pattern = "%#{query}%"

    Question
    |> where(topic_id: ^topic_id)
    |> where([q], like(q.prompt, ^pattern))
    |> order_by(asc: :position)
    |> Repo.all()
    |> attach_last_editor()
  end

  defp attach_last_editor([]), do: []

  defp attach_last_editor(questions) do
    question_ids = Enum.map(questions, & &1.id)

    latest_ids =
      from v in QuestionVersion,
        where: v.question_id in ^question_ids,
        group_by: v.question_id,
        select: %{id: max(v.id)}

    version_user =
      from(v in QuestionVersion,
        join: u in assoc(v, :user),
        join: lv in subquery(latest_ids),
        on: v.id == lv.id,
        select: %{question_id: v.question_id, name: u.name}
      )
      |> Repo.all()

    editor_map = Map.new(version_user, &{&1.question_id, &1.name})

    Enum.map(questions, fn q ->
      Map.put(q, :last_editor_name, Map.get(editor_map, q.id))
    end)
  end

  def get_question!(id) do
    Question
    |> preload(:topic)
    |> Repo.get!(id)
  end

  def create_question(attrs) do
    topic_id = Map.get(attrs, "topic_id") || Map.get(attrs, :topic_id)

    %Question{}
    |> Question.changeset(Map.drop(attrs, ["topic_id", :topic_id]) |> normalize_option_strings())
    |> Ecto.Changeset.put_change(:topic_id, topic_id)
    |> Repo.insert()
  end

  def update_question(question, attrs) do
    question
    |> Question.changeset(normalize_option_strings(attrs))
    |> Repo.update()
  end

  defp normalize_option_strings(attrs) when is_map(attrs) do
    case Map.get(attrs, :options) do
      opts when is_list(opts) ->
        Map.put(attrs, :options, Enum.map(opts, &normalize_one_option/1))

      _ ->
        attrs
    end
  end

  defp normalize_one_option(opt) when is_binary(opt), do: %{"text" => opt}
  defp normalize_one_option(opt) when is_map(opt), do: opt

  def delete_question(question) do
    Repo.delete(question)
  end

  def change_question(question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  # --- Question Versions (edit history) ---

  def create_question_version!(question, user, action) do
    %QuestionVersion{}
    |> QuestionVersion.changeset(%{
      question_id: question.id,
      user_id: user && user.id,
      prompt: question.prompt,
      options: question.options,
      correct_index: question.correct_index,
      image: question.image,
      action: action
    })
    |> Repo.insert!()
  end

  def list_question_versions(question_id) do
    QuestionVersion
    |> where(question_id: ^question_id)
    |> order_by(desc: :inserted_at)
    |> preload(:user)
    |> Repo.all()
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
    team_count = Map.get(attrs, "team_count") || Map.get(attrs, :team_count) || 5
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
    # DB foreign keys with on_delete: :delete_all handle cascading:
    # quiz_events → teams → answers (via team_id)
    # quiz_events → rounds → answers (via round_id)
    Repo.delete(event)
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

  defp generate_unique_code(tries \\ 10)

  defp generate_unique_code(0) do
    raise "could not generate unique event code after 10 attempts"
  end

  defp generate_unique_code(tries) do
    code = generate_code()

    if Repo.get_by(QuizEvent, code: code) do
      generate_unique_code(tries - 1)
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

  # --- Results ---

  def get_event_results(event_id) do
    event = get_event_with_teams!(event_id)
    teams = Enum.filter(event.teams, & &1.claimed_at)

    rounds =
      Round
      |> where(quiz_event_id: ^event_id)
      |> order_by(asc: :round_number)
      |> preload(:topic)
      |> Repo.all()

    answers = list_answers_for_event(event_id)

    answer_lookup =
      Enum.reduce(answers, %{}, fn answer, acc ->
        Map.put(acc, {answer.round_id, answer.question_id, answer.team_id}, answer.selected_index)
      end)

    rounds_data =
      Enum.map(rounds, fn round ->
        %{round: round, questions: list_questions_for_topic(round.topic_id)}
      end)

    standings =
      teams
      |> Enum.map(fn team ->
        score =
          Enum.count(answers, fn answer ->
            answer.team_id == team.id and answer.selected_index == answer.question.correct_index
          end)

        {team.id, team.name, score}
      end)
      |> Enum.sort_by(&elem(&1, 2), :desc)

    %{
      event: event,
      teams: teams,
      rounds_data: rounds_data,
      answer_lookup: answer_lookup,
      standings: standings
    }
  end
end
