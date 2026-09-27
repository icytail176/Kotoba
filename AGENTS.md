//
//  AGENTS.md
//  Kotoba
//
//  Created by Fumi on 2026/6/16.
//
# Kotoba Project Instructions

## Product

Kotoba is a native macOS application for Chinese-speaking users
who are learning Japanese vocabulary.

## Core technologies

- Swift
- SwiftUI
- SwiftData
- AVFAudio
- Native macOS application
- Local-first architecture
- No server in version 1
- No third-party dependency unless explicitly approved
- No external AI API in version 1

## Main features

- Daily study dashboard
- Japanese vocabulary flashcards
- Spaced repetition
- Maximum review interval of 60 days
- Japanese word and example sentence speech
- Keyboard shortcuts
- Vocabulary management
- UTF-8 CSV import
- Study statistics
- Local persistence

## Review rules

For a new word:

- again: 10 minutes
- hard: 1 day
- good: 2 days
- easy: 4 days

For a review word:

- again: enter relearning and schedule after 10 minutes
- hard: ceil(current interval × 1.2)
- good: ceil(current interval × 2.0)
- easy: ceil(current interval × 3.0)

All day-based intervals must be capped at 60 days.

After a lapse, the relearning ratings are:

- again: 10 minutes
- hard: 1 day
- good: 2 days
- easy: 4 days

The scheduling logic must not depend on SwiftUI.

## Architecture

Use a feature-oriented structure:

- App
- Models
- Features/Home
- Features/Study
- Features/Wordbook
- Features/Import
- Features/Statistics
- Features/Settings
- Services
- Components
- Resources
- Tests

Keep data, scheduling, import and speech logic outside SwiftUI views.

## User interface

- Native macOS interface
- Simplified Chinese user-facing text
- Japanese-compatible text display
- NavigationSplitView for main navigation
- Support window resizing
- Support light and dark mode
- Support full keyboard operation
- Prefer SF Symbols
- Avoid unnecessary animation

## Data safety

- Never delete vocabulary without confirmation
- Never reset study progress without confirmation
- Validate CSV before importing
- One invalid row must not crash the entire import
- Show the CSV row number and error reason
- Never silently overwrite duplicate vocabulary
- Never delete existing user data during schema changes

## Code quality

- Avoid force unwraps
- Avoid global mutable state
- Keep views small and composable
- Use dependency injection for services
- Use a deterministic clock in scheduler tests
- Add tests for scheduling, queue building and CSV import
- Do not rewrite unrelated files
- Do not add third-party packages without approval

## Workflow

Before changing code:

1. Inspect relevant files.
2. Explain the proposed implementation.
3. Make the smallest coherent change.
4. Build the project.
5. Run relevant tests.
6. Fix all introduced errors.
7. Summarize changed files and limitations.
