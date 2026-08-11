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
  Returns all topics that have at least one question, as lightweight
  `%{id, name}` maps. Used by the engine to build available_topics lists.
  """
  def list_topic_names do
    Topic
    |> where(enabled: true)
    |> join(:inner, [t], q in assoc(t, :questions))
    |> where([_t, q], q.status == "published")
    |> group_by([t], t.id)
    |> order_by([t], asc: t.name)
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

  @doc """
  Filters a list of `%{id, name}` topic maps to those that are enabled and
  have at least one question.
  """
  def filter_topics_with_questions(topics) when is_list(topics) do
    topic_ids = Enum.map(topics, & &1.id)

    ids_active =
      from(t in Topic,
        where: t.id in ^topic_ids and t.enabled == true,
        join: q in assoc(t, :questions),
        where: q.status == "published",
        group_by: t.id,
        select: t.id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(topics, &MapSet.member?(ids_active, &1.id))
  end

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

  @doc """
  Returns just the question ids for a topic, in position order. Cheaper than
  `list_questions_for_topic/1` (no row data, no last-editor join) — use when
  only the ordering is needed, e.g. computing a reorder.
  """
  def list_question_ids_for_topic(topic_id) do
    from(q in Question,
      where: q.topic_id == ^topic_id,
      order_by: [asc: q.position],
      select: q.id
    )
    |> Repo.all()
  end

  def list_published_questions_for_topic(topic_id) do
    Question
    |> where(topic_id: ^topic_id, status: "published")
    |> order_by(asc: :position)
    |> Repo.all()
  end

  @doc """
  Loads the published questions for a topic, shaped into the lightweight maps
  the quiz engine consumes (with `position` set from order, blank images
  normalized to nil). Shared by `EngineState.choose_topic/3` and
  `Engine` state recovery so the two never drift.
  """
  def load_questions_for_engine(topic_id) do
    list_published_questions_for_topic(topic_id)
    |> Enum.with_index()
    |> Enum.map(fn {q, idx} ->
      %{
        id: q.id,
        prompt: q.prompt,
        options: q.options,
        correct_index: q.correct_index,
        position: idx,
        images: Enum.reject(q.images || [], &(&1 in [nil, ""])),
        image_position: q.image_position || "left",
        layout: q.layout || "image_side"
      }
    end)
  end

  @doc """
  Loads questions for several topics in a single query (plus one batched
  last-editor query), grouped by `topic_id`. Used by the results page to avoid
  an N+1 per round.
  """
  def list_questions_for_topics(topic_ids) do
    topic_ids = Enum.reject(topic_ids, &is_nil/1)

    questions =
      from(q in Question,
        where: q.topic_id in ^topic_ids,
        order_by: [asc: q.topic_id, asc: q.position]
      )
      |> Repo.all()
      |> attach_last_editor()

    Enum.group_by(questions, & &1.topic_id)
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
    |> Ecto.Changeset.put_change(:position, next_question_position(topic_id))
    |> Repo.insert()
  end

  defp next_question_position(nil), do: 0

  defp next_question_position(topic_id) do
    case Repo.one(from q in Question, where: q.topic_id == ^topic_id, select: max(q.position)) do
      nil -> 0
      max -> max + 1
    end
  end

  @doc """
  Reorders all questions of a topic. `ordered_ids` must contain exactly the
  ids of the topic's questions; each question's position is set to its index
  in the list. Returns `{:ok, questions}` or `{:error, :mismatch}`.
  """
  def reorder_questions(topic_id, ordered_ids) when is_list(ordered_ids) do
    current_ids =
      from(q in Question, where: q.topic_id == ^topic_id, select: q.id)
      |> Repo.all()

    if Enum.sort(current_ids) == Enum.sort(ordered_ids) do
      Repo.transaction(fn ->
        ordered_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, index} ->
          from(q in Question, where: q.id == ^id, update: [set: [position: ^index]])
          |> Repo.update_all([])
        end)

        list_questions_for_topic(topic_id)
      end)
    else
      {:error, :mismatch}
    end
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
      images: question.images,
      layout: question.layout,
      action: action
    })
    |> Repo.insert!()
  end

  @doc """
  Non-raising version of `create_question_version!/3`. Returns
  `{:ok, version}` | `{:error, changeset}` so callers that have already
  persisted the question don't crash on a best-effort history row.
  """
  def create_question_version(question, user, action) do
    %QuestionVersion{}
    |> QuestionVersion.changeset(%{
      question_id: question.id,
      user_id: user && user.id,
      prompt: question.prompt,
      options: question.options,
      correct_index: question.correct_index,
      images: question.images,
      layout: question.layout,
      action: action
    })
    |> Repo.insert()
  end

  def list_question_versions(question_id) do
    QuestionVersion
    |> where(question_id: ^question_id)
    |> order_by(desc: :inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  # --- Quiz Events ---

  @active_statuses ~w(topic_selection question round_reveal)

  @doc "Statuses that mean a quiz is actively in progress (lobby/finished excluded)."
  def active_statuses, do: @active_statuses

  @doc "True when the event status is one of `active_statuses/0`."
  def status_active?(status) when is_binary(status), do: status in @active_statuses

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
  Claims a specific team slot by 0-based slot_index. Idempotent: returns
  {:ok, team} whether the slot was just claimed or already claimed — the
  printed QR card is the source of truth for "whoever holds it IS this team".
  Returns {:error, :not_found} if no team has the given slot_index.
  """
  def claim_team_slot(event, slot_index) do
    teams = list_teams_for_event(event.id)

    case Enum.find(teams, fn t -> t.slot_index == slot_index end) do
      nil ->
        {:error, :not_found}

      team ->
        result =
          if team.claimed_at do
            {:ok, team}
          else
            team
            |> Team.changeset(%{claimed_at: DateTime.utc_now()})
            |> Repo.update()
          end

        broadcast_team_update(event.id)
        result
    end
  end

  @doc """
  Assigns a random UUID token to every team of an event that doesn't already
  have one. Tokens are stable per team row, so a team can be tracked across
  quiz runs — but only finished quizzes with >1 round get them (the host
  decides via this call). Returns the list of updated teams.
  """
  def assign_team_tokens(event_id) do
    event = get_event_with_teams!(event_id)

    event.teams
    |> Enum.reject(& &1.token)
    |> Enum.each(fn team ->
      team
      |> Team.changeset(%{token: Ecto.UUID.generate()})
      |> Repo.update()
    end)

    list_teams_for_event(event_id)
  end

  @doc """
  Checks if a team belongs to a specific event.
  """
  def team_belongs_to_event?(team_id, event_id) do
    team = Repo.get(Team, team_id)
    team != nil and team.quiz_event_id == event_id
  end

  @doc """
  Unclaims a team slot: clears claimed_at and resets the name.
  The slot becomes available for a new team to claim.
  """
  def unclaim_team(team_id) do
    team = get_team!(team_id)
    default_name = Names.generate(existing_team_names(team.quiz_event_id))

    result =
      team
      |> Team.changeset(%{claimed_at: nil, name: default_name})
      |> Repo.update()

    broadcast_team_update(team.quiz_event_id)
    result
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
    |> Enum.map_join(fn _ -> Integer.to_string(:crypto.strong_rand_range(10)) end)
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

  @doc """
  Returns `%{team_id => correct_count}` for all correct answers across the
  given rounds in a single query. Used by engine state recovery to rebuild
  standings without an N+1 over rounds.
  """
  def count_correct_answers_for_rounds(round_ids) do
    Answer
    |> join(:inner, [a], q in assoc(a, :question))
    |> where([a], a.round_id in ^round_ids)
    |> where([a, q], a.selected_index == q.correct_index)
    |> group_by([a], a.team_id)
    |> select([a], {a.team_id, count(a.id)})
    |> Repo.all()
    |> Map.new()
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

    topic_ids = Enum.map(rounds, & &1.topic_id)
    questions_by_topic = list_questions_for_topics(topic_ids)

    answer_lookup =
      Enum.reduce(answers, %{}, fn answer, acc ->
        Map.put(acc, {answer.round_id, answer.question_id, answer.team_id}, answer.selected_index)
      end)

    rounds_data =
      Enum.map(rounds, fn round ->
        %{round: round, questions: Map.get(questions_by_topic, round.topic_id, [])}
      end)

    # One pass over answers to tally correct picks per team, instead of
    # scanning the full answer list once per team.
    correct_by_team =
      Enum.reduce(answers, %{}, fn answer, acc ->
        if answer.selected_index == answer.question.correct_index do
          Map.update(acc, answer.team_id, 1, &(&1 + 1))
        else
          acc
        end
      end)

    standings =
      teams
      |> Enum.map(fn team -> {team.id, team.name, Map.get(correct_by_team, team.id, 0)} end)
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
