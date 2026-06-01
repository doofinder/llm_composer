if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.Providers.Bedrock.HttpClientTest do
    use ExUnit.Case, async: true

    alias LlmComposer.Providers.Bedrock.HttpClient

    setup do
      Application.delete_env(:llm_composer, :tesla_adapter)
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    describe "request/5 non-streaming via Mint" do
      test "returns ok with status and body on 200", %{bypass: bypass} do
        Bypass.expect_once(bypass, "POST", "/test", fn conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(200, ~s({"result":"ok"}))
        end)

        assert {:ok, %{status_code: 200, body: ~s({"result":"ok"})}} =
                 HttpClient.request(:post, endpoint(bypass, "/test"), "", [], [])
      end

      test "returns ok with non-200 status code", %{bypass: bypass} do
        Bypass.expect_once(bypass, "POST", "/test", fn conn ->
          Plug.Conn.resp(conn, 500, "internal error")
        end)

        assert {:ok, %{status_code: 500, body: "internal error"}} =
                 HttpClient.request(:post, endpoint(bypass, "/test"), "", [], [])
      end
    end

    describe "request/5 streaming via Mint" do
      test "returns lazy stream that yields body chunks", %{bypass: bypass} do
        Bypass.expect_once(bypass, "POST", "/stream", fn conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/octet-stream")
          |> Plug.Conn.resp(200, "hello world")
        end)

        assert {:ok, %{status_code: 200, body: stream}} =
                 HttpClient.request(:post, endpoint(bypass, "/stream"), "", [], stream: true)

        assert Enum.join(stream) == "hello world"
      end

      test "returns status and headers before consuming stream", %{bypass: bypass} do
        Bypass.expect_once(bypass, "POST", "/stream", fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-custom", "value")
          |> Plug.Conn.resp(200, "data")
        end)

        assert {:ok, %{status_code: 200, headers: headers}} =
                 HttpClient.request(:post, endpoint(bypass, "/stream"), "", [], stream: true)

        assert Enum.any?(headers, fn {k, _v} -> k == "x-custom" end)
      end
    end

    describe "request/5 connection errors" do
      test "returns error fast on refused connection (non-streaming)" do
        assert {:error, %{reason: _}} =
                 HttpClient.request(:post, "http://localhost:1/test", "", [], [])
      end

      test "returns error fast on refused connection (streaming)" do
        assert {:error, %{reason: _}} =
                 HttpClient.request(:post, "http://localhost:1/test", "", [], stream: true)
      end
    end

    describe "configurable receive_timeout" do
      setup do
        original_bedrock = Application.get_env(:llm_composer, :bedrock)

        on_exit(fn ->
          if is_nil(original_bedrock) do
            Application.delete_env(:llm_composer, :bedrock)
          else
            Application.put_env(:llm_composer, :bedrock, original_bedrock)
          end
        end)

        :ok
      end

      test "non-streaming request honours bedrock receive_timeout", %{bypass: bypass} do
        Application.put_env(:llm_composer, :bedrock, receive_timeout: 50)

        Bypass.expect_once(bypass, "POST", "/timeout", fn conn ->
          Process.sleep(500)
          Plug.Conn.send_resp(conn, 200, "")
        end)

        result = HttpClient.request(:post, endpoint(bypass, "/timeout"), "", [], [])
        Bypass.pass(bypass)

        assert {:error, %{reason: :timeout}} = result
      end

      test "streaming request honours bedrock receive_timeout", %{bypass: bypass} do
        Application.put_env(:llm_composer, :bedrock, receive_timeout: 50)

        Bypass.expect_once(bypass, "POST", "/stream-timeout", fn conn ->
          Process.sleep(500)
          Plug.Conn.send_resp(conn, 200, "")
        end)

        result =
          HttpClient.request(:post, endpoint(bypass, "/stream-timeout"), "", [], stream: true)

        Bypass.pass(bypass)

        assert {:error, %{reason: :timeout_waiting_for_status}} = result
      end
    end

    defp endpoint(bypass, path), do: "http://localhost:#{bypass.port}#{path}"
  end
end
