defmodule LlmComposer.Application do
  @moduledoc false
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications

  use Application

  @spec start(term, term) :: Supervisor.on_start()
  def start(_type, _args) do
    cache_mod = Application.get_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)

    children =
      if cache_mod == LlmComposer.Cache.Ets do
        [{LlmComposer.Cache.Ets, []}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: LlmComposer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
