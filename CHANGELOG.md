# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **System Prompt Handling**: Added support for an optional system prompt in `run_completion/3`. The `system_prompt` is now treated as `nil` when not provided.
- **Custom Message Flow Example**: Updated the `README.md` with an example of how to use the `run_completion/3` function directly with a custom message history.
- **Nil Message Handling in Models**: Handling the `nil` case when system_prompt not provided
  
## [0.2.0] - 2024-10-01

### Added
- Initial release with support for basic message handling, interaction with OpenAI and Ollama models, and a foundational structure for model settings and function execution.

---

