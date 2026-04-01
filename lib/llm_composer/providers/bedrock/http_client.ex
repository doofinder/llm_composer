if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.Providers.Bedrock.HttpClient do
    @moduledoc """
    ExAws HTTP client for Bedrock that delegates to the configured Tesla Finch adapter.

    When `stream: true` is present in `http_opts`, uses `Finch.stream/5` in a spawned
    process, forwarding events as messages to the caller. Returns a lazy `Stream` as the
    response body — required for the ConverseStream binary event-stream response.

    For regular requests (or when streaming is not requested), uses `Finch.request/3`.

    Reads the Finch process name from the `:llm_composer` `:tesla_adapter` config:

        config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch}

    If Finch is not configured, logs a warning and attempts a fallback via
    `ExAws.Request.Hackney` when available.
    """

    @behaviour ExAws.Request.HttpClient

    alias ExAws.Request.Hackney

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
          stream_request(method, url, body, headers, name)

        {true, :error} ->
          Logger.warning(
            "[bedrock] Finch not configured in :llm_composer :tesla_adapter — " <>
              "falling back to full response. " <>
              "Add `config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch}` " <>
              "for proper stream support."
          )

          full_request_fallback(method, url, body, headers)

        {false, {:ok, name}} ->
          regular_request(method, url, body, headers, name)

        {false, :error} ->
          full_request_fallback(method, url, body, headers)
      end
    end

    @spec stream_request(atom(), binary(), binary(), list(), atom()) ::
            {:ok, map()} | {:error, map()}
    defp stream_request(method, url, body, headers, finch_name) do
      req = Finch.build(method, url, headers, body)
      caller = self()

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

      case await_response_metadata() do
        {:ok, {status, resp_headers}} ->
          chunk_stream =
            Stream.resource(
              fn -> :ok end,
              fn state ->
                receive do
                  {:bedrock_stream, {:data, chunk}} -> {[chunk], state}
                  {:bedrock_stream, :done} -> {:halt, state}
                after
                  @stream_timeout -> {:halt, state}
                end
              end,
              fn _state -> :ok end
            )

          {:ok, %{status_code: status, headers: resp_headers, body: chunk_stream}}

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end

    @spec await_response_metadata() :: {:ok, {pos_integer(), list()}} | {:error, term()}
    defp await_response_metadata do
      receive do
        {:bedrock_stream, {:status, status}} ->
          receive do
            {:bedrock_stream, {:headers, resp_headers}} ->
              {:ok, {status, resp_headers}}
          after
            @stream_timeout -> {:error, :timeout_waiting_for_headers}
          end
      after
        @stream_timeout -> {:error, :timeout_waiting_for_status}
      end
    end

    @spec regular_request(atom(), binary(), binary(), list(), atom()) ::
            {:ok, map()} | {:error, map()}
    defp regular_request(method, url, body, headers, finch_name) do
      req = Finch.build(method, url, headers, body)

      case Finch.request(req, finch_name) do
        {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
          {:ok, %{status_code: status, headers: resp_headers, body: resp_body}}

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end

    @spec full_request_fallback(atom(), binary(), binary(), list()) ::
            {:ok, map()} | {:error, map()}
    defp full_request_fallback(method, url, body, headers) do
      if Code.ensure_loaded?(Hackney) do
        Hackney.request(method, url, body, headers, [])
      else
        {:error, %{reason: :no_http_client_available}}
      end
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
