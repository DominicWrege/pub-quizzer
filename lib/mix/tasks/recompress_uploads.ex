defmodule Mix.Tasks.RecompressUploads do
  @moduledoc """
  Re-compresses existing uploads at the current quality settings and
  generates missing thumbnail variants.

  Run with `mix recompress_uploads`.
  """
  use Mix.Task

  @thumb_prefix "thumb_"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    upload_dir = PubQuizzer.upload_dir()
    File.mkdir_p!(upload_dir)

    files =
      File.ls!(upload_dir)
      |> Enum.reject(&String.starts_with?(&1, @thumb_prefix))
      |> Enum.filter(fn name ->
        ext = Path.extname(name) |> String.downcase()
        ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"]
      end)

    Enum.each(files, fn name ->
      src = Path.join(upload_dir, name)
      dest = Path.join(upload_dir, name)
      thumb = Path.join(upload_dir, @thumb_prefix <> name)

      # Re-compress main image at current quality
      tmp = Path.join(System.tmp_dir!(), "recompress-#{name}")

      args = [
        "-y",
        "-i",
        src,
        "-vf",
        "scale=w=1280:h=1280:force_original_aspect_ratio=decrease",
        "-q:v",
        "10",
        tmp
      ]

      case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
        {_output, 0} ->
          File.cp!(tmp, dest)
          File.rm(tmp)

        {output, _} ->
          Mix.shell().error("  ✗ #{name}: #{String.slice(output, 0, 200)}")
      end

      # Generate thumbnail if missing
      unless File.exists?(thumb) do
        thumb_args = [
          "-y",
          "-i",
          src,
          "-vf",
          "scale=w=480:h=480:force_original_aspect_ratio=decrease",
          "-q:v",
          "15",
          thumb
        ]

        case System.cmd("ffmpeg", thumb_args, stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, _} -> Mix.shell().error("  ✗ thumb #{name}: #{String.slice(output, 0, 200)}")
        end
      end
    end)

    Mix.shell().info("Recompressed #{length(files)} uploads.")
  end
end
