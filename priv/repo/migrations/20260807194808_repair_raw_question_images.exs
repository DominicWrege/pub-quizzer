defmodule PubQuizzer.Repo.Migrations.RepairRawQuestionImages do
  use Ecto.Migration
  import Ecto.Query

  # ReplaceImageWithImages copied the old `image` column into `images` by
  # binding an Elixir list, which exqlite stored as a *raw string*
  # (e.g. "/uploads/x.jpg") instead of a JSON array ("[\"/uploads/x.jpg\"]").
  # Such rows crash when loaded into the {:array, :string} field. This repairs
  # any affected row by re-encoding its value as a proper JSON array.
  #
  # Idempotent: rows that already hold a valid JSON array are left untouched, so
  # this is a no-op on databases that were never affected.
  def up do
    repo().all(from(q in "questions", select: [q.id, q.images]))
    |> Enum.each(&repair_row/1)
  end

  def down, do: :ok

  defp repair_row([_id, nil]), do: :ok

  defp repair_row([id, raw]) when is_binary(raw) do
    case Jason.decode(raw) do
      # Already a valid JSON array — nothing to repair.
      {:ok, list} when is_list(list) ->
        :ok

      _ ->
        images = if String.trim(raw) == "", do: [], else: [raw]
        json = Jason.encode!(images)

        repo().update_all(
          from(q in "questions", where: q.id == ^id, update: [set: [images: ^json]]),
          []
        )
    end
  end

  defp repair_row(_), do: :ok
end
