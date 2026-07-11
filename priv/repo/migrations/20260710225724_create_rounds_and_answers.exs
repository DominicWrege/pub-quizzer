defmodule PubQuizzer.Repo.Migrations.CreateRoundsAndAnswers do
  use Ecto.Migration

  def change do
    create table(:rounds) do
      add :round_number, :integer, null: false
      add :topic_id, references(:topics, on_delete: :nilify_all)
      add :quiz_event_id, references(:quiz_events, on_delete: :delete_all), null: false
      add :chosen_by_team_id, references(:teams, on_delete: :nilify_all)
      add :winner_team_id, references(:teams, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:rounds, [:quiz_event_id])
    create index(:rounds, [:quiz_event_id, :round_number])

    create table(:answers) do
      add :selected_index, :integer, null: false
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :round_id, references(:rounds, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:answers, [:round_id])
    create index(:answers, [:round_id, :question_id])
    create unique_index(:answers, [:round_id, :question_id, :team_id])
  end
end
