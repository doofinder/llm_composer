defmodule LlmComposer.Providers.UtilsTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.Utils

  test "get_req_opts returns stream adapter when stream_response true" do
    assert Utils.get_req_opts(stream_response: true) == [adapter: [response: :stream]]
  end

  test "get_req_opts returns empty list when stream_response not set" do
    assert Utils.get_req_opts([]) == []
  end
end
