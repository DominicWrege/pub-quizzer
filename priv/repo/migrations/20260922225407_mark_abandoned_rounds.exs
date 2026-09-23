defmodule PubQuizzer.Repo.Migrations.MarkAbandonedRounds do
  use Ecto.Migration

  def change do
    alter table(:rounds) do
      add :abandoned, :boolean, default: false, null: false
    end
  end
end
