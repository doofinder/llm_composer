if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.Providers.Bedrock.HttpClient do
    @moduledoc """
    ExAws HTTP client for Bedrock using Mint by default, with optional Finch support.

    When `stream: true` is present in `http_opts`, uses streaming HTTP via a spawned
    process that forwards events as messages to the caller. Returns a lazy `Stream` as
    the response body — required for the ConverseStream binary event-stream response.

    The spawned task is monitored with `Process.monitor/1` so any unexpected crash
    surfaces immediately to the caller instead of waiting for the stream timeout.

    ## Default behaviour (Mint)

    Uses `Mint.HTTP` directly for both streaming and regular requests. No additional
    configuration is required since Mint is a required dependency of `llm_composer`.

    ## Finch (optional)

    If the `:llm_composer` `:tesla_adapter` config is set to a Finch adapter, Finch
    is used instead of Mint:

        config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch}

    Finch must be started in your supervision tree:

        children = [{Finch, name: MyFinch}]
    """

    @behaviour ExAws.Request.HttpClient

    require Logger

    @stream_timeout 30_000

    @impl ExAws.Request.HttpClient
    @spec request(
            ExAws.Request.HttpClient.http_method(),
            binary(),
            binary(),
            list(),
            keyword()
          ) ::
            {:ok, %{status_code: pos_integer(), headers: list(), body: term()}}
            | {:error, %{reason: term()}}
    def request(method, url, body, headers, http_opts) do
      stream = Keyword.get(http_opts, :stream, false)

      case {stream, finch_name()} do
        {true, {:ok, name}} ->
          Logger.debug("[bedrock] http_client=finch name=#{name} stream=true")
          stream_request_finch(method, url, body, headers, name)

        {true, :error} ->
          Logger.debug("[bedrock] http_client=mint stream=true")
          stream_request_mint(method, url, body, headers)

        {false, {:ok, name}} ->
          Logger.debug("[bedrock] http_client=finch name=#{name} stream=false")
          regular_request_finch(method, url, body, headers, name)

        {false, :error} ->
          Logger.debug("[bedrock] http_client=mint stream=false")
          regular_request_mint(method, url, body, headers)
      end
    end

    # ---------------------------------------------------------------------------
    # Finch streaming
    # ---------------------------------------------------------------------------

    @spec stream_request_finch(atom(), binary(), binary(), list(), atom()) ::
            {:ok, map()} | {:error, map()}
    defp stream_request_finch(method, url, body, headers, finch_name) do
      req = Finch.build(method, url, headers, body)
      caller = self()

      {:ok, pid} =
        Task.start(fn ->
          Finch.stream(req, finch_name, nil, fn
            {:status, status}, _acc ->
              send(caller, {:bedrock_stream, {:status, status}})

            {:headers, resp_headers}, _acc ->
              send(caller, {:bedrock_stream, {:headers, resp_headers}})

            {:data, chunk}, _acc ->
              send(caller, {:bedrock_stream, {:data, chunk}})

            _, _acc ->
              nil
          end)

          send(caller, {:bedrock_stream, :done})
        end)

      ref = Process.monitor(pid)
      handle_stream_response(ref)
    end

    # ---------------------------------------------------------------------------
    # Finch regular request
    # ---------------------------------------------------------------------------

    @spec regular_request_finch(atom(), binary(), binary(), list(), atom()) ::
            {:ok, map()} | {:error, map()}
    defp regular_request_finch(method, url, body, headers, finch_name) do
      req = Finch.build(method, url, headers, body)

      case Finch.request(req, finch_name) do
        {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
          {:ok, %{status_code: status, headers: resp_headers, body: resp_body}}

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end

    # ---------------------------------------------------------------------------
    # Mint streaming
    # ---------------------------------------------------------------------------

    @spec stream_request_mint(atom(), binary(), binary(), list()) ::
            {:ok, map()} | {:error, map()}
    defp stream_request_mint(method, url, body, headers) do
      caller = self()

      {:ok, pid} =
        Task.start(fn ->
          case mint_connect_and_request(method, url, body, headers) do
            {:ok, conn, ref} ->
              stream_mint_loop(conn, ref, caller)

            {:error, reason} ->
              send(caller, {:bedrock_stream, {:error, reason}})
          end
        end)

      ref = Process.monitor(pid)
      handle_stream_response(ref)
    end

    @spec stream_mint_loop(Mint.HTTP.t(), Mint.Types.request_ref(), pid()) :: :ok
    defp stream_mint_loop(conn, ref, caller) do
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            {:ok, conn, responses} ->
              if process_mint_responses(responses, ref, caller) do
                send(caller, {:bedrock_stream, :done})
              else
                stream_mint_loop(conn, ref, caller)
              end

            {:error, _conn, reason, _responses} ->
              send(caller, {:bedrock_stream, {:error, reason}})

            :unknown ->
              stream_mint_loop(conn, ref, caller)
          end
      after
        @stream_timeout ->
          send(caller, {:bedrock_stream, :done})
      end
    end

    @spec process_mint_responses(list(), Mint.Types.request_ref(), pid()) :: boolean()
    defp process_mint_responses([], _ref, _caller), do: false

    defp process_mint_responses([{:status, ref, status} | rest], ref, caller) do
      send(caller, {:bedrock_stream, {:status, status}})
      process_mint_responses(rest, ref, caller)
    end

    defp process_mint_responses([{:headers, ref, resp_headers} | rest], ref, caller) do
      send(caller, {:bedrock_stream, {:headers, resp_headers}})
      process_mint_responses(rest, ref, caller)
    end

    defp process_mint_responses([{:data, ref, chunk} | rest], ref, caller) do
      send(caller, {:bedrock_stream, {:data, chunk}})
      process_mint_responses(rest, ref, caller)
    end

    defp process_mint_responses([{:done, ref} | _rest], ref, _caller), do: true

    defp process_mint_responses([_other | rest], ref, caller),
      do: process_mint_responses(rest, ref, caller)

    # ---------------------------------------------------------------------------
    # Mint regular request
    # ---------------------------------------------------------------------------

    @spec regular_request_mint(atom(), binary(), binary(), list()) ::
            {:ok, map()} | {:error, map()}
    defp regular_request_mint(method, url, body, headers) do
      case mint_connect_and_request(method, url, body, headers) do
        {:ok, conn, ref} ->
          collect_mint_response(conn, ref, %{status: nil, headers: [], body: ""})

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end

    @spec collect_mint_response(Mint.HTTP.t(), Mint.Types.request_ref(), map()) ::
            {:ok, map()} | {:error, map()}
    defp collect_mint_response(conn, ref, acc) do
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            {:ok, conn, responses} ->
              acc =
                Enum.reduce(responses, acc, fn
                  {:status, ^ref, status}, acc -> %{acc | status: status}
                  {:headers, ^ref, hs}, acc -> %{acc | headers: acc.headers ++ hs}
                  {:data, ^ref, chunk}, acc -> %{acc | body: acc.body <> chunk}
                  {:done, ^ref}, acc -> Map.put(acc, :done, true)
                  _other, acc -> acc
                end)

              if Map.get(acc, :done) do
                {:ok, %{status_code: acc.status, headers: acc.headers, body: acc.body}}
              else
                collect_mint_response(conn, ref, acc)
              end

            {:error, _conn, reason, _responses} ->
              {:error, %{reason: reason}}

            :unknown ->
              collect_mint_response(conn, ref, acc)
          end
      after
        @stream_timeout -> {:error, %{reason: :timeout}}
      end
    end

    # ---------------------------------------------------------------------------
    # Shared helpers
    # ---------------------------------------------------------------------------

    @spec mint_connect_and_request(atom(), binary(), binary(), list()) ::
            {:ok, Mint.HTTP.t(), Mint.Types.request_ref()} | {:error, term()}
    defp mint_connect_and_request(method, url, body, headers) do
      uri = URI.parse(url)
      scheme = String.to_existing_atom(uri.scheme)
      port = uri.port || if(scheme == :https, do: 443, else: 80)
      path = if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path || "/"

      method_str =
        method
        |> to_string()
        |> String.upcase()

      with {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, port) do
        Mint.HTTP.request(conn, method_str, path, headers, body)
      end
    end

    @spec handle_stream_response(reference()) :: {:ok, map()} | {:error, map()}
    defp handle_stream_response(ref) do
      case await_response_metadata(ref) do
        {:ok, {status, resp_headers}} when status in 200..299 ->
          {:ok, %{status_code: status, headers: resp_headers, body: build_chunk_stream(ref)}}

        {:ok, {status, resp_headers}} ->
          {:ok, %{status_code: status, headers: resp_headers, body: collect_error_body(ref)}}

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end

    @spec await_response_metadata(reference()) ::
            {:ok, {pos_integer(), list()}} | {:error, term()}
    defp await_response_metadata(ref) do
      receive do
        {:bedrock_stream, {:status, status}} ->
          receive do
            {:bedrock_stream, {:headers, resp_headers}} ->
              {:ok, {status, resp_headers}}

            {:bedrock_stream, {:error, reason}} ->
              {:error, reason}

            {:DOWN, ^ref, :process, _pid, reason} ->
              {:error, {:task_crashed, reason}}
          after
            @stream_timeout -> {:error, :timeout_waiting_for_headers}
          end

        {:bedrock_stream, {:error, reason}} ->
          {:error, reason}

        {:DOWN, ^ref, :process, _pid, reason} ->
          {:error, {:task_crashed, reason}}
      after
        @stream_timeout -> {:error, :timeout_waiting_for_status}
      end
    end

    @spec collect_error_body(reference(), binary()) :: binary()
    defp collect_error_body(ref, acc \\ "") do
      receive do
        {:bedrock_stream, {:data, chunk}} -> collect_error_body(ref, acc <> chunk)
        {:bedrock_stream, :done} -> acc
        {:bedrock_stream, {:error, _reason}} -> acc
        {:DOWN, ^ref, :process, _pid, _reason} -> acc
      after
        @stream_timeout -> acc
      end
    end

    @spec build_chunk_stream(reference()) :: Enumerable.t()
    defp build_chunk_stream(ref) do
      Stream.resource(
        fn -> :ok end,
        fn state ->
          receive do
            {:bedrock_stream, {:data, chunk}} -> {[chunk], state}
            {:bedrock_stream, :done} -> {:halt, state}
            {:bedrock_stream, {:error, _reason}} -> {:halt, state}
            {:DOWN, ^ref, :process, _pid, _reason} -> {:halt, state}
          after
            @stream_timeout -> {:halt, state}
          end
        end,
        fn _state -> :ok end
      )
    end

    @spec finch_name() :: {:ok, atom()} | :error
    defp finch_name do
      case Application.get_env(:llm_composer, :tesla_adapter) do
        {Tesla.Adapter.Finch, opts} when is_list(opts) -> Keyword.fetch(opts, :name)
        _ -> :error
      end
    end
  end
end
