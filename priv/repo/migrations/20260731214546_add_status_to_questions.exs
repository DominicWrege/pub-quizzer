defmodule PubQuizzer.Repo.Migrations.AddStatusToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :status, :string, default: "published", null: false
    end
  end
end
