if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.Providers.Bedrock.StreamOperation do
    @moduledoc false

    @doc """
    Custom ExAws operation for the Bedrock ConverseStream endpoint.

    Returns the raw binary body instead of JSON-decoding it, since the
    ConverseStream response uses AWS Event Stream binary encoding.
    """

    defstruct http_method: :post,
              path: "/",
              data: %{},
              headers: [],
              service: nil

    @type t :: %__MODULE__{}

    @spec new(map(), String.t()) :: t()
    def new(payload, model) do
      %__MODULE__{
        data: payload,
        headers: [{"Content-Type", "application/json"}],
        http_method: :post,
        path: "/model/#{model}/converse-stream",
        service: :"bedrock-runtime"
      }
    end
  end

  defimpl ExAws.Operation, for: LlmComposer.Providers.Bedrock.StreamOperation do
    @spec perform(LlmComposer.Providers.Bedrock.StreamOperation.t(), map()) ::
            {:ok, binary()} | {:error, term()}
    def perform(operation, config) do
      url = ExAws.Request.Url.build(operation, config)
      headers = [{"x-amz-content-sha256", ""} | operation.headers]

      config = Map.put(config, :http_client, LlmComposer.Providers.Bedrock.HttpClient)

      result =
        ExAws.Request.request(
          operation.http_method,
          url,
          operation.data,
          headers,
          config,
          operation.service
        )

      case ExAws.Request.default_aws_error(result) do
        {:ok, %{body: body}} -> {:ok, body}
        {:error, _} = error -> error
      end
    end

    @spec stream!(LlmComposer.Providers.Bedrock.StreamOperation.t(), any()) :: no_return()
    def stream!(_, _) do
      raise ArgumentError, "stream! is not supported for Bedrock.StreamOperation"
    end
  end
end
