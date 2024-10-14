defmodule LlmComposer.Errors do
  defmodule MissingKeyError do
    defexception message: "API key is missing"
  end
end
