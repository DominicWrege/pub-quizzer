defmodule PubQuizzer.Repo.Migrations.AddPaperRoundFallback do
  use Ecto.Migration

  def change do
    alter table(:rounds) do
      add :paper_team_ids, {:array, :integer}, default: [], null: false
      add :paper_submitted_team_ids, {:array, :integer}, default: [], null: false
    end

    alter table(:answers) do
      add :source, :string, default: "digital", null: false
      add :recorded_by_user_id, references(:users, on_delete: :nilify_all)
    end
  end
end
