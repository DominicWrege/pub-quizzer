defmodule PubQuizzer.Uploads do
  @moduledoc """
  Image storage for question/option uploads.

  Uploaded files are de-duplicated by a SHA-256 hash of their content (same
  bytes ⇒ same URL), and — when ffmpeg is available — transcoded to a bounded
  JPEG plus a 480px thumbnail. Both behaviours live here so the LiveView stays
  free of filesystem/codec concerns.
  """

  require Logger

  @doc """
  Stores an uploaded image, returning `{:ok, "/uploads/<filename>"}`.

  With ffmpeg: writes a max-1280px JPEG + a `thumb_` 480px JPEG.
  Without ffmpeg: copies the original under a content-hashed name and warns.
  """
  def store_compressed(tmp_path) do
    dir = PubQuizzer.upload_dir()
    File.mkdir_p!(dir)
    base = content_hash(tmp_path)

    if System.find_executable("ffmpeg") do
      filename = base <> ".jpg"
      dest = Path.join(dir, filename)
      thumb_dest = Path.join(dir, "thumb_" <> filename)
      compress_with_ffmpeg(tmp_path, dest, thumb_dest)
    else
      Logger.warning("ffmpeg not found, copying original file")
      filename = base <> source_extension(tmp_path)
      dest = Path.join(dir, filename)
      File.cp!(tmp_path, dest)
      {:ok, "/uploads/#{filename}"}
    end
  end

  # Names uploads by a SHA-256 hash of their content: collision-free, stable
  # across re-uploads, and safe to cache immutably (same bytes => same URL).
  defp content_hash(path) do
    path
    |> File.stream!([], 65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.url_encode64(padding: false)
  end

  defp source_extension(path) do
    case path |> Path.extname() |> String.downcase() do
      "" -> ".jpg"
      ext -> ext
    end
  end

  defp compress_with_ffmpeg(tmp_path, dest, thumb_dest) do
    filename = Path.basename(dest)

    args = [
      "-y",
      "-i",
      tmp_path,
      "-vf",
      "scale=w=1920:h=1920:force_original_aspect_ratio=decrease",
      "-q:v",
      "5",
      dest
    ]

    thumb_args = [
      "-y",
      "-i",
      tmp_path,
      "-vf",
      "scale=w=768:h=768:force_original_aspect_ratio=decrease",
      "-q:v",
      "10",
      thumb_dest
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        case System.cmd("ffmpeg", thumb_args, stderr_to_stdout: true) do
          {_thumb_output, 0} ->
            :ok

          {thumb_output, _} ->
            Logger.warning("thumbnail generation failed: #{thumb_output}")
        end

        {:ok, "/uploads/#{filename}"}

      {output, _exit_code} ->
        Logger.warning("ffmpeg compression failed, using original: #{output}")
        File.cp!(tmp_path, dest)
        {:ok, "/uploads/#{filename}"}
    end
  end
end
