defmodule PubQuizzer.Repo.Migrations.ReplaceImageWithImages do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:questions) do
      add :images, {:array, :string}, default: [], null: false
    end

    flush()

    # Schemaless queries carry no type info, so dump the array explicitly —
    # otherwise the raw string is stored instead of a JSON array.
    repo().all(from(q in "questions", select: [q.id, q.image]))
    |> Enum.each(fn
      [_id, nil] ->
        :ok

      [_id, ""] ->
        :ok

      [id, image] ->
        {:ok, dumped} = Ecto.Type.dump({:array, :string}, [image])

        # The update goes inside the `from` macro so the pin is valid —
        # `repo().update_all/2` is a runtime call where `set: [images: ^v]`
        # would be a misplaced pin (not a macro-compiled option).
        repo().update_all(
          from(q in "questions", where: q.id == ^id, update: [set: [images: ^dumped]]),
          []
        )
    end)

    flush()

    alter table(:questions) do
      remove :image
    end

    alter table(:question_versions) do
      add :images, {:array, :string}
    end
  end

  def down do
    alter table(:questions) do
      add :image, :string
    end

    flush()

    repo().all(from(q in "questions", select: [q.id, q.images]))
    |> Enum.each(fn
      [_id, nil] ->
        :ok

      [_id, ""] ->
        :ok

      [id, json] when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, [first | _]} ->
            repo().update_all(from(q in "questions", where: q.id == ^id), set: [image: first])

          _ ->
            :ok
        end

      [id, [first | _]] ->
        repo().update_all(from(q in "questions", where: q.id == ^id), set: [image: first])

      [_id, []] ->
        :ok
    end)

    flush()

    alter table(:questions) do
      remove :images
    end

    alter table(:question_versions) do
      remove :images
    end
  end
end
