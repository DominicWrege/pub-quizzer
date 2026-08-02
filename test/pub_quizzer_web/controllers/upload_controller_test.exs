defmodule PubQuizzerWeb.UploadControllerTest do
  use PubQuizzerWeb.ConnCase, async: false

  # Mutates the global :upload_dir application env, so must not run async.
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    original = Application.get_env(:pub_quizzer, :upload_dir)
    Application.put_env(:pub_quizzer, :upload_dir, tmp_dir)
    on_exit(fn -> Application.put_env(:pub_quizzer, :upload_dir, original) end)
    {:ok, dir: tmp_dir}
  end

  test "serves an existing upload with correct content type and cache headers", %{
    conn: conn,
    dir: dir
  } do
    File.write!(Path.join(dir, "abc123.jpg"), "fakejpegbytes")

    conn = get(conn, ~p"/uploads/abc123.jpg")

    assert response(conn, 200) == "fakejpegbytes"
    assert hd(get_resp_header(conn, "content-type")) =~ "image/jpeg"
    assert hd(get_resp_header(conn, "cache-control")) =~ "immutable"
  end

  test "serves thumbnail variants", %{conn: conn, dir: dir} do
    File.write!(Path.join(dir, "thumb_abc123.jpg"), "thumbbytes")

    conn = get(conn, ~p"/uploads/thumb_abc123.jpg")

    assert response(conn, 200) == "thumbbytes"
  end

  test "returns 404 for a missing file", %{conn: conn} do
    conn = get(conn, ~p"/uploads/nope.jpg")

    assert response(conn, 404)
  end

  test "blocks path traversal out of the upload dir", %{conn: conn, dir: dir} do
    File.write!(Path.join(Path.dirname(dir), "secret.txt"), "secret")

    # %2F keeps "../secret.txt" inside a single :filename segment so it reaches
    # the controller, which must reject it rather than serve the parent file.
    conn = get(conn, "/uploads/..%2Fsecret.txt")

    assert response(conn, 404)
  end
end
