defmodule LlmComposer.Model do
  @moduledoc """
  Behaviour definition for LLM models.
  """

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @callback run([Message.t()], Message.t(), keyword()) ::
              {:ok, LlmResponse.t()} | {:error, term()}

  @callback model_id() :: atom
end
