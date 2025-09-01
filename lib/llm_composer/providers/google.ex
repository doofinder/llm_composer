defmodule LlmComposer.Providers.Google do
  @moduledoc """
  Provider implementation for Google

  This provider supports Google's Generative AI API and Vertex AI platform,
  offering comprehensive features including function calls, streaming responses,
  structured outputs, and auto function execution.

  ## Dependencies

  ### For Google AI API
  No additional dependencies required.

  ### For Vertex AI
  - **Goth**: Required for OAuth 2.0 authentication with Google Cloud Platform
    Add to your `mix.exs`:
    ```elixir
    {:goth, "~> 1.3"}
    ```

  ## Provider Options

  The third argument of `run/3` accepts the following options in `provider_opts`:

  ### Required Options

  * `:model` - The Gemini model to use (e.g., "gemini-2.5-flash")

  ### Authentication Options

  * `:api_key` - Google API key (overrides application config, for Google AI API only)
  * `:vertex` - Vertex AI configuration map (see Vertex AI section below)
  * `:google_goth` - Name of the Goth process for Vertex AI authentication (overrides application config)

  ### Request Options

  * `:stream_response` - Boolean to enable streaming responses (default: false)
  * `:request_params` - Map of additional request parameters to merge with the request body
  * `:functions` - List of function definitions for tool calling

  ### Response Format Options

  * `:response_format` - Map defining structured output schema for JSON responses

  ## Vertex AI Configuration

  To use Vertex AI instead of the standard Google AI API, provide a `:vertex` map with:

  ### Required Vertex Fields
  * `:project_id` - Your Google Cloud project ID
  * `:location_id` - The location/region for your Vertex AI endpoint (e.g., "us-central1", "global")

  ### Optional Vertex Fields
  * `:api_endpoint` - Custom API endpoint (overrides default regional endpoint)

  ## Examples

  ### Basic Google AI API Usage
  ```elixir
  opts = [
    model: "gemini-2.5-flash",
    api_key: "your-api-key"
  ]
  ```

  ### Vertex AI Usage with Goth Setup

  First, set up Goth in your application. This example shows manual Goth setup:

  ```elixir
  # Read service account credentials
  google_json = File.read!(Path.expand("~/path/to/service-account.json"))
  credentials = Jason.decode!(google_json)
  source = {:service_account, credentials}

  # Configure HTTP client for Goth (optional, if using llm_composer you could use Tesla)
  http_client = fn opts ->
    client = Tesla.client([{Tesla.Middleware.Retry, delay: 500, max_retries: 2}])
    Tesla.request(client, opts)
  end

  # Start Goth process
  {:ok, _pid} = Goth.start_link([
    source: source, 
    http_client: http_client, 
    name: MyApp.Goth
  ])

  # Configure LlmComposer to use your Goth process
  Application.put_env(:llm_composer, :google_goth, MyApp.Goth)

  # Provider options
  opts = [
    model: "gemini-2.5-flash",
    vertex: %{
      project_id: "my-gcp-project",
      location_id: "global"
    }
  ]
  ```

  ### Vertex AI with Supervision Tree

  For production applications, add Goth to your supervision tree:

  ```elixir
  # In your application.ex
  def start(_type, _args) do
    google_json = File.read!(Application.get_env(:my_app, :google_credentials_path))
    credentials = Jason.decode!(google_json)
    
    children = [
      # Other children...
      {Goth, name: MyApp.Goth, source: {:service_account, credentials}},
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Configure in config.exs
  config :llm_composer, :google_goth, MyApp.Goth
  ```

  ## Authentication

  ### Google AI API
  Set your API key in application config:
  ```elixir
  config :llm_composer, :google_key, "your-google-ai-api-key"
  ```

  Or pass it directly in options:
  ```elixir
  opts = [model: "gemini-pro", api_key: "your-key"]
  ```

  ### Vertex AI with Goth

  Vertex AI requires OAuth 2.0 authentication handled by Goth. You need:

  1. **Service Account**: Create a service account in Google Cloud Console with appropriate permissions
  2. **Credentials File**: Download the JSON credentials file for your service account  
  3. **Goth Process**: Start a Goth process with your service account credentials
  4. **Configuration**: Configure LlmComposer to use your Goth process name

  #### Service Account Permissions
  Your service account needs the following IAM roles:
  - `Vertex AI User` or `Vertex AI Service Agent`
  - `Service Account Token Creator` (if using impersonation)

  #### Goth Configuration Options

  Configure the Goth process name in your application config:
  ```elixir
  config :llm_composer, :google_goth, MyApp.Goth
  ```

  Or pass it directly in provider options:
  ```elixir
  opts = [
    model: "gemini-pro",
    google_goth: MyApp.Goth,
    vertex: %{project_id: "my-project", location_id: "global"}
  ]
  ```

  ## Error Handling

  The provider returns:
  * `{:ok, response}` on successful requests
  * `{:error, :model_not_provided}` when model is not specified
  * `{:error, reason}` for API errors, network issues, or Goth authentication failures

  ## Supported Features

  * ✅ Basic chat completion
  * ✅ Streaming responses
  * ✅ Function/tool calling
  * ✅ Auto function execution
  * ✅ Structured outputs (JSON schema)
  * ✅ System instructions
  * ✅ Vertex AI platform support

  ## Notes

  * When using Vertex AI, the base URL construction differs from standard Google AI API
  * Streaming is not compatible with Tesla retries
  * Function declarations are wrapped in Google's expected format automatically
  * Request parameters in `:request_params` are merged with the final request body
  * Goth handles token refresh automatically for Vertex AI authentication
  * Ensure your service account has proper permissions for Vertex AI access
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  require Logger

  @base_url Application.compile_env(
              :llm_composer,
              :google_url,
              "https://generativelanguage.googleapis.com/v1beta/models/"
            )

  @impl LlmComposer.Provider
  def name, do: :google

  @impl LlmComposer.Provider
  @doc """
  Reference: https://ai.google.dev/api/generate-content
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)

    {base_url, headers} = get_request_data(opts)

    client = HttpClient.client(base_url, opts)

    req_opts = Utils.get_req_opts(opts)

    # stream or generate?
    suffix =
      if Keyword.get(opts, :stream_response) do
        "streamGenerateContent?alt=sse"
      else
        "generateContent"
      end

    if model do
      messages
      |> build_request(system_message, opts)
      |> then(&Tesla.post(client, "/#{model}:#{suffix}", &1, headers: headers, opts: req_opts))
      |> handle_response()
      |> LlmResponse.new(name())
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools(name())

    # custom request params if provided
    req_params = Keyword.get(opts, :request_params, %{})

    %{
      contents: Utils.map_messages(messages, name())
    }
    |> maybe_add_system_instructs(system_message)
    |> maybe_add_structured_outputs(opts)
    |> maybe_add_tools(tools)
    |> Map.merge(req_params)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: 200, body: body}}) do
    actions = Utils.extract_actions(body)
    {:ok, %{response: body, actions: actions}}
  end

  defp handle_response({:ok, resp}) do
    {:error, resp}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp get_key do
    case Application.get_env(:llm_composer, :google_key) do
      nil -> raise MissingKeyError
      key -> key
    end
  end

  @spec maybe_add_system_instructs(map(), map() | nil) :: map()
  defp maybe_add_system_instructs(base_req, nil), do: base_req

  defp maybe_add_system_instructs(base_req, system_message) do
    Map.put(base_req, :system_instruction, %{
      "parts" => [%{"text" => system_message.content}]
    })
  end

  @spec maybe_add_structured_outputs(map(), keyword()) :: map()
  defp maybe_add_structured_outputs(base_req, opts) do
    case Keyword.get(opts, :response_format) do
      nil ->
        base_req

      response_schema ->
        Map.put(base_req, :generationConfig, %{
          responseMimeType: "application/json",
          responseSchema: response_schema
        })
    end
  end

  @spec maybe_add_tools(map(), map() | nil) :: map()
  defp maybe_add_tools(base_req, []), do: base_req

  defp maybe_add_tools(base_req, tools) do
    Map.put(base_req, :tools, [%{"functionDeclarations" => tools}])
  end

  defp get_request_data(opts) do
    case Keyword.get(opts, :vertex) do
      nil ->
        token = Keyword.get(opts, :api_key) || get_key()
        headers = [{"X-GOOG-API-KEY", token}]
        {@base_url, headers}

      %{project_id: project_id, location_id: location_id} = vertex ->
        name = Keyword.get(opts, :google_goth) || Application.get_env(:llm_composer, :google_goth)

        %{token: token} = Goth.fetch!(name)

        api_endpoint = get_vertex_endpoint(vertex, location_id)

        base_url =
          "https://#{api_endpoint}/v1/projects/#{project_id}/locations/#{location_id}/publishers/google/models"

        headers = [{"Authorization", "Bearer #{token}"}]
        {base_url, headers}
    end
  end

  @spec get_vertex_endpoint(map(), String.t()) :: String.t()
  defp get_vertex_endpoint(%{api_endpoint: custom_endpoint}, _location), do: custom_endpoint
  defp get_vertex_endpoint(_data, "global"), do: "aiplatform.googleapis.com"
  defp get_vertex_endpoint(_data, location_id), do: "#{location_id}-aiplatform.googleapis.com"
end
