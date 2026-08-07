defmodule PubQuizzerWeb.UploadController do
  use PubQuizzerWeb, :controller

  @cache_control "public, max-age=31536000, immutable"

  def show(conn, %{"filename" => filename}) do
    dir = PubQuizzer.upload_dir()
    path = Path.expand(Path.join(dir, filename))

    if safe_upload_path?(path, dir) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> put_resp_header("cache-control", @cache_control)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_file(200, path)
    else
      conn
      |> put_status(:not_found)
      |> put_resp_header("cache-control", "no-cache")
      |> text("not found")
    end
  end

  # Guards against directory traversal (prefix check on the expanded path),
  # non-files, and symlinks inside the upload dir pointing elsewhere (Path.expand
  # resolves ".." but not symlinks, which would pass the prefix check).
  defp safe_upload_path?(path, dir) do
    String.starts_with?(path, dir <> "/") and
      File.regular?(path) and
      not symlink?(path)
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> true
      _ -> false
    end
  end
end
