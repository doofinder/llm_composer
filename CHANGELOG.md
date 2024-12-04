# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.3] - 2024-12-03
- **Timeouts**: Configurable OpenAI's timeout. Default set to 50 seconds.

## [0.3.2] - 2024-12-03
- **Timeouts**: Fix OpenAI-timeout handling and increase Tesla's timeout to 5 seconds.

## [0.3.1] - 2024-10-14

### Added
- **Error Handling**: Introduced a new module `LlmComposer.Errors` with a custom `MissingKeyError` for better error management.
- **Removed Legacy Code**: Removed the `get_messages/4` function from `LlmComposer` to streamline message handling.

## [0.3.0] - 2024-10-10

### Added
- **System Prompt Handling**: Added support for an optional system prompt in `run_completion/3`. The `system_prompt` is now treated as `nil` when not provided.
- **Custom Message Flow Example**: Updated the `README.md` with an example of how to use the `run_completion/3` function directly with a custom message history.
- **Nil Message Handling in Models**: Handling the `nil` case when system_prompt not provided

## [0.2.0] - 2024-10-01

### Added
- Initial release with support for basic message handling, interaction with OpenAI and Ollama models, and a foundational structure for model settings and function execution.

---
[Unreleased]: https://github.com/doofinder/llm_composer/compare/0.3.1...HEAD
[0.3.2]: https://github.com/doofinder/llm_composer/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/doofinder/llm_composer/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/doofinder/llm_composer/compare/0.2.0...0.3.0
[0.3.0]: https://github.com/doofinder/llm_composer/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/doofinder/llm_composer/compare/d9f96d55859300d779d9c3899b4c33578bb2e362...0.2.0
[first commit]: https://github.com/doofinder/llm_composer/commit/d9f96d55859300d779d9c3899b4c33578bb2e362
