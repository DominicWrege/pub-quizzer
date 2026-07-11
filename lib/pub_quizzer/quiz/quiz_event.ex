defmodule PubQuizzer.Quiz.QuizEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(lobby topic_selection question round_reveal finished)

  schema "quiz_events" do
    field :code, :string
    field :name, :string
    field :status, :string, default: "lobby"
    field :team_count, :integer, default: 6
    field :current_round, :integer, default: 0
    field :current_question_index, :integer, default: 0
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    has_many :teams, PubQuizzer.Quiz.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :code,
      :name,
      :status,
      :team_count,
      :current_round,
      :current_question_index,
      :started_at,
      :finished_at
    ])
    |> validate_required([:code, :status, :team_count])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:team_count, greater_than: 0, less_than_or_equal_to: 20)
    |> unique_constraint(:code)
  end
end
