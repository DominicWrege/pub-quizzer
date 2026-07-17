defmodule PubQuizzer.Repo.Migrations.CreateQuestionVersions do
  use Ecto.Migration

  def change do
    create table(:question_versions) do
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :prompt, :string, null: false
      add :options, {:array, :string}, null: false
      add :correct_index, :integer, null: false
      add :image, :string
      add :action, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:question_versions, [:question_id])
  end
end
