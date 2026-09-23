defmodule PubQuizzer.Repo.Migrations.SnapshotRoundQuestions do
  use Ecto.Migration

  def change do
    alter table(:rounds) do
      add :questions_snapshot, {:array, :map}, default: [], null: false
    end
  end
end
