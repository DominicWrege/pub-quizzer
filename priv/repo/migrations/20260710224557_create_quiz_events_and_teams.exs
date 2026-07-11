defmodule PubQuizzer.Repo.Migrations.CreateQuizEventsAndTeams do
  use Ecto.Migration

  def change do
    create table(:quiz_events, strict: true) do
      add :code, :string, null: false
      add :status, :string, null: false, default: "lobby"
      add :team_count, :integer, null: false, default: 6
      add :current_round, :integer, null: false, default: 0
      add :current_question_index, :integer, null: false, default: 0
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quiz_events, [:code])

    create table(:teams, strict: true) do
      add :name, :string, null: false
      add :slot_index, :integer, null: false
      add :claimed_at, :utc_datetime
      add :quiz_event_id, references(:quiz_events, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:teams, [:quiz_event_id])
    create index(:teams, [:quiz_event_id, :slot_index])
  end
end
