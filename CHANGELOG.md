# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2023-01-08

### Added

- GitHub Actions workflows to test Elixir 1.12-1.14 and OTP 23-25 (thanks @warmwaffles / #1)

### Fixed

- Update tests to support change in `Function.info/1` between OTP 24 and 25
- Support Elixir 1.12 in `mix.exs`
- Use `reraise` instead of `raise` when not wrapping exceptions

### Changed

- Created test for nested steps

