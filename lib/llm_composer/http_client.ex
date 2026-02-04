defmodule LlmComposer.HttpClient do
  @moduledoc """
  Helper mod for setup the Tesla http client and its options
  """

  @default_timeout 50_000

  @spec client(binary(), keyword()) :: Tesla.Client.t()
  def client(base_url, opts \\ []) do
    base_url
    |> middlewares(opts)
    |> Tesla.client(adapter())
  end

  @spec adapter() :: term()
  defp adapter do
    Application.get_env(:llm_composer, :tesla_adapter, Tesla.Adapter.Mint)
  end

  @spec middlewares(binary(), keyword()) :: list(term())
  defp middlewares(base_url, opts) do
    stream = Keyword.get(opts, :stream_response)

    resp = [
      {
        Tesla.Middleware.BaseUrl,
        base_url
      },
      Tesla.Middleware.JSON
    ]

    cond do
      stream ->
        resp ++ [{Tesla.Middleware.SSE, only: :data}]

      retries_disabled?(opts) ->
        resp ++
          [
            {Tesla.Middleware.Timeout,
             timeout:
               Keyword.get(
                 opts,
                 :timeout,
                 Application.get_env(:llm_composer, :timeout, @default_timeout)
               )}
          ]

      true ->
        resp ++
          [
            {Tesla.Middleware.Retry, retry_opts(opts)},
            {Tesla.Middleware.Timeout,
             timeout:
               Keyword.get(
                 opts,
                 :timeout,
                 Application.get_env(:llm_composer, :timeout, @default_timeout)
               )}
          ]
    end
  end

  @spec retries_disabled?(keyword()) :: boolean()
  defp retries_disabled?(opts) do
    skip_config = Application.get_env(:llm_composer, :skip_retries, false)

    # Only the explicit skip flag disables retries. Let Tesla handle other retry options
    Keyword.get(opts, :skip_retries, skip_config)
  end

  @spec retry_opts(keyword()) :: keyword()
  defp retry_opts(opts) do
    config = Application.get_env(:llm_composer, :retry_opts, [])
    req_opts = Keyword.get(opts, :retry_opts, [])

    []
    |> Keyword.merge(config)
    |> Keyword.merge(req_opts)
    |> Keyword.put_new(:delay, 1_000)
    |> Keyword.put_new(:max_delay, 10_000)
    |> Keyword.put_new(:should_retry, &default_should_retry/1)
  end

  @spec default_should_retry(term()) :: boolean()
  defp default_should_retry({:ok, %{status: status}}) when status in [429, 500, 503], do: true
  defp default_should_retry({:error, :closed}), do: true
  defp default_should_retry(_other), do: false
end
