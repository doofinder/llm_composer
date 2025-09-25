defmodule LlmComposer.SettingsTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Settings

  describe "struct creation" do
    test "creates settings with default values" do
      settings = %Settings{}

      assert settings.api_key == nil
      assert settings.auto_exec_functions == false
      assert settings.functions == []
      assert settings.provider == nil
      assert settings.provider_opts == nil
      assert settings.providers == nil
      assert settings.stream_response == false
      assert settings.system_prompt == nil
      assert settings.track_costs == false
      assert settings.user_prompt_prefix == ""
    end

    test "creates settings with custom values" do
      functions = [%{name: "test", mf: {TestModule, :test}}]
      providers = [{TestProvider, [model: "gpt-4"]}]

      settings = %Settings{
        api_key: "test-key",
        auto_exec_functions: true,
        functions: functions,
        provider: TestProvider,
        provider_opts: [model: "gpt-3.5"],
        providers: providers,
        stream_response: true,
        system_prompt: "You are a helpful assistant",
        track_costs: true,
        user_prompt_prefix: "User: "
      }

      assert settings.api_key == "test-key"
      assert settings.auto_exec_functions == true
      assert settings.functions == functions
      assert settings.provider == TestProvider
      assert settings.provider_opts == [model: "gpt-3.5"]
      assert settings.providers == providers
      assert settings.stream_response == true
      assert settings.system_prompt == "You are a helpful assistant"
      assert settings.track_costs == true
      assert settings.user_prompt_prefix == "User: "
    end

    test "creates minimal settings for basic usage" do
      settings = %Settings{
        providers: [{LlmComposer.Providers.OpenAI, [model: "gpt-4"]}],
        system_prompt: "You are a helpful assistant"
      }

      assert settings.providers == [{LlmComposer.Providers.OpenAI, [model: "gpt-4"]}]
      assert settings.system_prompt == "You are a helpful assistant"
      assert settings.api_key == nil
      assert settings.auto_exec_functions == false
    end
  end

  describe "type specifications" do
    test "accepts valid types for all fields" do
      # This test ensures the struct can be created with types matching the spec
      settings = %Settings{
        api_key: "string",
        auto_exec_functions: true,
        functions: [],
        provider: LlmComposer.Providers.OpenAI,
        provider_opts: [model: "gpt-4"],
        providers: [{LlmComposer.Providers.OpenAI, []}],
        stream_response: false,
        system_prompt: "prompt",
        track_costs: false,
        user_prompt_prefix: "prefix"
      }

      assert %Settings{} = settings
    end
  end
end
