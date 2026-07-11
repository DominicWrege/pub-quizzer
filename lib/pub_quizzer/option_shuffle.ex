defmodule PubQuizzer.OptionShuffle do
  @moduledoc """
  Deterministic per-team option shuffling to prevent shoulder-surfing.

  Uses a seed derived from team_id, question_id, and round_number so the
  same team sees the same shuffle for the same question, but different
  teams see different shuffles.
  """

  @doc """
  Shuffles options deterministically. Returns {shuffled_options, index_map}
  where index_map maps shuffled_index → original_index.
  """
  def shuffle(options, team_id, question_id, round_number) do
    seed = :erlang.phash2({team_id, question_id, round_number})
    :rand.seed(:exsss, seed)

    indexed = Enum.with_index(options)
    shuffled = Enum.shuffle(indexed)

    shuffled_options = Enum.map(shuffled, fn {opt, _} -> opt end)

    index_map =
      Enum.with_index(shuffled) |> Enum.map(fn {{_, orig}, shuf} -> {shuf, orig} end) |> Map.new()

    {shuffled_options, index_map}
  end

  @doc """
  Translates a shuffled index back to the original index.
  """
  def to_original(index_map, shuffled_index) do
    Map.get(index_map, shuffled_index, shuffled_index)
  end

  @doc """
  Translates an original index to the shuffled index.
  """
  def to_shuffled(index_map, original_index) do
    index_map
    |> Enum.find(fn {_, orig} -> orig == original_index end)
    |> case do
      {shuf, _} -> shuf
      nil -> original_index
    end
  end
end
