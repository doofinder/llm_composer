defmodule LlmComposer.HttpClient do
  @moduledoc """
  Helper mod for setup the Tesla http client and its options
  """

  @default_timeout 50_000
  @default_max_retries 3

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
               Application.get_env(:llm_composer, :timeout) ||
                 Keyword.get(opts, :default_timeout, @default_timeout)}
          ]

      true ->
        resp ++
          [
            {Tesla.Middleware.Retry, retry_opts(opts)},
            {Tesla.Middleware.Timeout,
             timeout:
               Application.get_env(:llm_composer, :timeout) ||
                 Keyword.get(opts, :default_timeout, @default_timeout)}
          ]
    end
  end

  @spec retries_disabled?(keyword()) :: boolean()
  defp retries_disabled?(opts) do
    config = Application.get_env(:llm_composer, :retry, [])

    Keyword.get(opts, :retry) == false ||
      Keyword.get(config, :enabled) == false ||
      Keyword.get(opts, :max_retries) == 0 ||
      Keyword.get(config, :max_retries) == 0
  end

  @spec retry_opts(keyword()) :: keyword()
  defp retry_opts(opts) do
    config = Application.get_env(:llm_composer, :retry, [])

    delay = Keyword.get(opts, :retry_delay) || Keyword.get(config, :delay, :timer.seconds(1))

    max_delay =
      Keyword.get(opts, :retry_max_delay) || Keyword.get(config, :max_delay, :timer.seconds(10))

    max_retries =
      Keyword.get(opts, :max_retries) || Keyword.get(config, :max_retries, @default_max_retries)

    [
      delay: delay,
      max_delay: max_delay,
      max_retries: max_retries,
      should_retry: fn
        {:ok, %{status: status}} when status in [429, 500, 503] -> true
        {:error, :closed} -> true
        _other -> false
      end
    ]
  end
end
