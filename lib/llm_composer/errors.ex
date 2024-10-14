defmodule LlmComposer.Errors do
  @moduledoc """
  Custom errors in here
  """

  defmodule MissingKeyError do
    defexception message: "API key is missing"
  end
end
