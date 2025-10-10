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

    if stream do
      resp ++ [{Tesla.Middleware.SSE, only: :data}]
    else
      resp ++
        [
          {Tesla.Middleware.Retry,
           delay: :timer.seconds(1),
           max_delay: :timer.seconds(10),
           max_retries: 10,
           should_retry: fn
             {:ok, %{status: status}} when status in [429, 500, 503] -> true
             {:error, :closed} -> true
             _other -> false
           end},
          {Tesla.Middleware.Timeout,
           timeout:
             Application.get_env(:llm_composer, :timeout) ||
               Keyword.get(opts, :default_timeout, @default_timeout)}
        ]
    end
  end
end
