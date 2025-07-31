import Config

config :llm_composer,
  openai_key: "",
  ollama_uri: "http://localhost:11434",
  open_router_key: "",
  tesla_adapter: nil,
  timeout: nil

import_config "#{Mix.env()}.exs"
