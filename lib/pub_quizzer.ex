defmodule PubQuizzer do
  @moduledoc """
  PubQuizzer keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Absolute directory where user-uploaded images are stored and served from.

  Defaults to `priv/uploads` (resolved against the current working directory,
  which is the repo root in dev). This is deliberately outside `priv/static`
  so `Plug.Static` never serves or raises over these files — they are served
  by `PubQuizzerWeb.UploadController`. In production releases this is
  overridden via the `UPLOAD_DIR` environment variable to a persistent,
  writable location such as `/var/lib/pub-quizzer/uploads`, because the
  release's `priv/static` lives in the read-only Nix store.
  """
  def upload_dir do
    :pub_quizzer
    |> Application.get_env(:upload_dir, "priv/uploads")
    |> Path.expand()
  end
end
