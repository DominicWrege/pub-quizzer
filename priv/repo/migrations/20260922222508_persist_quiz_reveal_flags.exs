defmodule PubQuizzer.Repo.Migrations.PersistQuizRevealFlags do
  use Ecto.Migration

  def change do
    alter table(:quiz_events) do
      add :standings_revealed, :boolean, default: false, null: false
      add :final_results_revealed, :boolean, default: false, null: false
    end
  end
end
