defmodule PubQuizzer.Repo.Migrations.CreateTopicsAndQuestions do
  use Ecto.Migration

  def change do
    create table(:topics, strict: true) do
      add :name, :string, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:topics, [:name])

    create table(:questions, strict: true) do
      add :prompt, :string, null: false
      add :options, {:array, :string}, null: false
      add :correct_index, :integer, null: false
      add :position, :integer, null: false, default: 0
      add :topic_id, references(:topics, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:questions, [:topic_id])
    create index(:questions, [:position])
  end
end
