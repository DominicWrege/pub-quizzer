defmodule PubQuizzer.Repo.Migrations.AddLinkCodeToTeams do
  use Ecto.Migration

  def up do
    alter table(:teams) do
      add :link_code, :string, null: false, default: ""
    end

    flush()

    repo().query!("SELECT id, quiz_event_id FROM teams ORDER BY id").rows
    |> Enum.group_by(fn [_id, event_id] -> event_id end)
    |> Enum.each(fn {_event_id, teams} ->
      codes =
        Stream.repeatedly(fn ->
          for <<byte <- :crypto.strong_rand_bytes(3)>>, into: "", do: <<?a + rem(byte, 26)>>
        end)
        |> Stream.uniq()
        |> Enum.take(length(teams))

      Enum.zip(teams, codes)
      |> Enum.each(fn {[id, _event_id], code} ->
        repo().query!("UPDATE teams SET link_code = ? WHERE id = ?", [code, id])
      end)
    end)

    create unique_index(:teams, [:quiz_event_id, :link_code])
  end

  def down do
    drop unique_index(:teams, [:quiz_event_id, :link_code])

    alter table(:teams) do
      remove :link_code
    end
  end
end
