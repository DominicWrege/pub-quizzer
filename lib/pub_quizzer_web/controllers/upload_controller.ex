defmodule PubQuizzerWeb.UploadController do
  use PubQuizzerWeb, :controller

  @cache_control "public, max-age=31536000, immutable"

  def show(conn, %{"filename" => filename}) do
    dir = PubQuizzer.upload_dir()
    path = Path.expand(Path.join(dir, filename))

    if String.starts_with?(path, dir <> "/") and File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> put_resp_header("cache-control", @cache_control)
      |> send_file(200, path)
    else
      conn
      |> put_status(:not_found)
      |> put_resp_header("cache-control", "no-cache")
      |> text("not found")
    end
  end
end
