defmodule LlmComposerTest do
  use ExUnit.Case, async: true
  doctest LlmComposer

  # Since most functions in LlmComposer require provider mocking for full testing,
  # we'll focus on doctests and basic functionality for now.
  # Integration tests with mocked providers will come later.
end
