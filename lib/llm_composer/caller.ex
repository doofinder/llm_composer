defmodule LlmComposer.Caller do
  @moduledoc """
  A module that provides a macro for generating functions to interact with language models.

  This module allows defining chat completion functions using a specific model, system prompt, and user prompt.
  """

  @doc """
  Generates functions for interacting with a language model.
  """
  defmacro __using__(opts) do
    # mandatory keys
    model_mod = Keyword.fetch!(opts, :model)
    system_prompt_opt = Keyword.fetch!(opts, :system_prompt)

    # optional keys
    model_opts_base = Keyword.get(opts, :model_opts, [])
    base_message = Keyword.get(opts, :user_prompt, "")
    message_replace_token = Keyword.get(opts, :replace_token, "@REPLACETHIS@")
    functions_opt = Keyword.get(opts, :functions, [])

    model_opts = Keyword.put(model_opts_base, :functions, functions_opt)
    auto_exec_functions = Keyword.get(opts, :auto_exec_functions, false)

    quote do
      require Logger

      @functions unquote(functions_opt)

      alias unquote(model_mod), as: LlmModel
      alias LlmComposer.Caller.Helpers
      alias LlmComposer.LlmResponse
      alias LlmComposer.Message

      @doc """
      Generates a chat completion based on the provided message and previous conversation history.

      Arguments
        * message (binary): Last message of the chat by the user.
        * old_message (list(map)): List of last messages between the chat and the user (if any)
        * opts (map): some options
          * user_prompt (binary): some user prompt for dynamic prompts instead of a hardcoded prompt.
            It accepts the :replace_token as a way of injecting the user message in a specific place.
      """
      @spec completion(binary, [map()], keyword()) :: {:ok, LlmResponse.t()} | {:error, term()}
      def completion(message, old_messages \\ [], opts \\ []) do
        messages = get_messages(message, old_messages, opts)
        llm_model_opts = Keyword.merge(unquote(model_opts), opts)

        run_completion(messages, llm_model_opts)
      end

      def simple_chat(msg) do
        messages = get_messages(msg, [], %{})

        run_completion(messages, unquote(model_opts))
      end

      @spec get_messages(binary, [map()], map()) :: [map()]
      defp get_messages(current_message, old_messages, opts) do
        Enum.reverse([user_message(current_message, opts) | old_messages])
      end

      @doc false
      @spec user_message(binary, map()) :: map()
      defp user_message(message, opts) do
        Message.new(:user, user_prompt(message, opts))
      end

      @doc false
      @spec user_prompt(binary, map()) :: binary
      defp user_prompt(message, opts) do
        prompt = Map.get(opts, :user_prompt, unquote(base_message))
        replace_token = unquote(message_replace_token)

        if String.contains?(prompt, replace_token) do
          String.replace(prompt, replace_token, message)
        else
          prompt <> message
        end
      end

      @spec run_completion([Message.t()], keyword(), LlmResponse.t() | nil) ::
              {:ok, LlmResponse.t()} | {:error, term()}
      defp run_completion(messages, llm_model_opts, previous_response \\ nil) do
        system_msg = Message.new(:system, unquote(system_prompt_opt))

        messages
        |> LlmModel.run(system_msg, llm_model_opts)
        |> then(fn
          {:ok, res} ->
            # set previous response all the time
            res = %LlmResponse{res | previous_response: previous_response}

            Logger.debug("input_tokens=#{res.input_tokens}, output_tokens=#{res.output_tokens}")

            if unquote(auto_exec_functions) do
              maybe_run_functions(res, messages, llm_model_opts)
            else
              {:ok, res}
            end

          {:error, data} = resp ->
            Logger.error("error in llm call: #{inspect(data)}")
            resp
        end)
      end

      @spec maybe_run_functions(LlmResponse.t(), [Message.t()], keyword()) :: term()
      defp maybe_run_functions(res, messages, llm_model_opts) do
        res
        |> Helpers.maybe_exec_functions(@functions)
        |> Helpers.maybe_complete_chat(messages, fn new_messages ->
          run_completion(new_messages, llm_model_opts, res)
        end)
      end
    end
  end
end
