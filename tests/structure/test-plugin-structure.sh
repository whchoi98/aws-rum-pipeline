#!/bin/bash
# 프로젝트 구조 및 매니페스트 검증.

echo "# Settings JSON validity"
assert_json_valid ".claude/settings.json" "settings.json is valid JSON"
assert_json_valid ".mcp.json" ".mcp.json is valid JSON"

echo "# Required root files"
assert_file_exists "CLAUDE.md" "root CLAUDE.md exists"
assert_file_exists "README.md" "README.md exists"
assert_file_exists ".gitignore" ".gitignore exists"
assert_file_exists ".editorconfig" ".editorconfig exists"
assert_file_exists ".env.example" ".env.example exists"
assert_file_exists "CHANGELOG.md" "CHANGELOG.md exists"

echo "# Required directories"
assert_dir_exists ".claude/hooks" ".claude/hooks/ exists"
assert_dir_exists ".claude/skills" ".claude/skills/ exists"
assert_dir_exists ".claude/commands" ".claude/commands/ exists"
assert_dir_exists ".claude/agents" ".claude/agents/ exists"
assert_dir_exists "docs/decisions" "docs/decisions/ exists"
assert_dir_exists "docs/runbooks" "docs/runbooks/ exists"
assert_dir_exists "scripts" "scripts/ exists"

echo "# Skills"
assert_file_exists ".claude/skills/code-review/SKILL.md" "code-review skill exists"
assert_file_exists ".claude/skills/refactor/SKILL.md" "refactor skill exists"
assert_file_exists ".claude/skills/release/SKILL.md" "release skill exists"
assert_file_exists ".claude/skills/sync-docs/SKILL.md" "sync-docs skill exists"

echo "# Commands"
assert_file_exists ".claude/commands/review.md" "review command exists"
assert_file_exists ".claude/commands/test-all.md" "test-all command exists"
assert_file_exists ".claude/commands/deploy.md" "deploy command exists"

echo "# Agents"
assert_file_exists ".claude/agents/code-reviewer.yml" "code-reviewer agent exists"
assert_file_exists ".claude/agents/security-auditor.yml" "security-auditor agent exists"

echo "# Module CLAUDE.md files"
for module_dir in terraform lambda sdk cdk simulator agentcore mobile-sdk-ios mobile-sdk-android scripts; do
    assert_file_exists "${module_dir}/CLAUDE.md" "${module_dir}/CLAUDE.md exists"
done

echo "# Documentation"
assert_file_exists "docs/architecture.md" "architecture.md exists"
assert_file_exists "docs/api-reference.md" "api-reference.md exists"
assert_file_exists "docs/onboarding.md" "onboarding.md exists"
assert_file_exists "docs/decisions/.template.md" "ADR template exists"
assert_file_exists "docs/runbooks/.template.md" "runbook template exists"

echo "# Scripts"
assert_file_exists "scripts/setup.sh" "setup.sh exists"
assert_file_exists "scripts/install-hooks.sh" "install-hooks.sh exists"
assert_executable "scripts/setup.sh" "setup.sh is executable"
assert_executable "scripts/install-hooks.sh" "install-hooks.sh is executable"

echo "# CLAUDE.md quality checks"
assert_contains "CLAUDE.md" "Project Structure" "CLAUDE.md has Project Structure section"
assert_contains "CLAUDE.md" "Key Commands" "CLAUDE.md has Key Commands section"
assert_contains "CLAUDE.md" "Conventions" "CLAUDE.md has Conventions section"
assert_contains "CLAUDE.md" "Auto-Sync Rules" "CLAUDE.md has Auto-Sync Rules section"

echo "# Skill content quality"
assert_contains ".claude/skills/code-review/SKILL.md" "Output Format\|출력 형식" "code-review skill has output format"
assert_contains ".claude/skills/code-review/SKILL.md" "confidence\|Confidence" "code-review skill defines confidence"
assert_contains ".claude/skills/release/SKILL.md" "On Failure\|실패" "release skill has error recovery"
assert_contains ".claude/skills/refactor/SKILL.md" "On Failure\|실패" "refactor skill has error recovery"
assert_contains ".claude/skills/sync-docs/SKILL.md" "On Failure\|실패" "sync-docs skill has error recovery"

echo "# Agent content quality"
assert_contains ".claude/agents/code-reviewer.yml" "system:" "code-reviewer agent has system prompt"
assert_contains ".claude/agents/security-auditor.yml" "system:" "security-auditor agent has system prompt"

echo "# Command content quality"
assert_contains ".claude/commands/deploy.md" "On Failure\|실패" "deploy command has error recovery"
assert_contains ".claude/commands/deploy.md" "STOP" "deploy command has user confirmation gate"
assert_contains ".claude/commands/test-all.md" "On Failure\|실패" "test-all command has error recovery"
assert_contains ".claude/commands/review.md" "On Failure\|실패" "review command has error recovery"

echo "# Settings deny list"
assert_contains ".claude/settings.json" "deny" "settings.json has deny list"
assert_contains ".claude/settings.json" "rm -rf" "deny list blocks rm -rf"
assert_contains ".claude/settings.json" "git push --force" "deny list blocks force push"
assert_contains ".claude/settings.json" "terraform destroy" "deny list blocks terraform destroy"
assert_contains ".claude/settings.json" "git clean" "deny list blocks git clean"
assert_contains ".claude/settings.json" "git checkout \." "deny list blocks git checkout ."
assert_contains ".claude/settings.json" "git restore \." "deny list blocks git restore ."
assert_contains ".claude/settings.json" "chmod 777" "deny list blocks chmod 777"
assert_contains ".claude/settings.json" "terraform apply -auto-approve" "deny list blocks terraform apply -auto-approve"
