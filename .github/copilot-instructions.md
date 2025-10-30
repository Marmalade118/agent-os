# Agent OS - AI Coding Agent Instructions

Agent OS is a structured framework for AI-driven development using spec-driven workflows and standardized agent behaviors. This system transforms AI agents from confused interns into productive developers through organized profiles, standards, and multi-phase workflows.

## Architecture Overview

The system is organized around **profiles** (default profile in `profiles/default/`) containing:
- **Standards**: Development patterns and conventions in `standards/{global,backend,frontend,testing}/`
- **Agents**: Specialized AI agents in `agents/` (implementer, spec-writer, verifier, etc.)
- **Commands**: Multi-phase workflows in `commands/` with both single-agent and multi-agent patterns
- **Workflows**: Reusable process templates in `workflows/`

## Key Workflow Patterns

### Multi-Phase Sequential Commands
Commands use numbered files that must execute in sequence:
```
commands/plan-product/single-agent/
  1-product-concept.md
  2-create-mission.md  
  3-create-roadmap.md
  4-create-tech-stack.md
```

### Template Substitution System
Agent OS uses `{{placeholder}}` syntax for dynamic content injection:
- `{{workflows/implementation/implement-tasks}}` - includes workflow content
- `{{standards/*}}` - includes all standards files
- `{{UNLESS standards_as_claude_code_skills}}` - conditional inclusion

### Agent Delegation Pattern
Commands can delegate to specialized agents using the `@agent-os/agents/[agent-name]` pattern, enabling complex multi-agent workflows.

## Essential Commands

- **Installation**: `./scripts/project-install.sh` - installs Agent OS into a project
- **Configuration**: Edit `config.yml` to set defaults for Claude Code commands, subagents, and standards handling
- **Profile switching**: Use `--profile` flag in installation scripts

## Standards Architecture

Standards are categorized and referenced by agents:
- `standards/global/` - Universal patterns (tech-stack.md, conventions.md, error-handling.md)
- `standards/backend/` - Server-side patterns (api.md, models.md, queries.md)
- `standards/frontend/` - Client-side patterns (components.md, css.md, accessibility.md)

Standards can be loaded as Claude Code Skills (template in `claude-code-skill-template.md`) or injected directly into prompts.

## Development Workflow

1. **Plan Product**: Use `commands/plan-product/` to establish mission, roadmap, and tech stack
2. **Write Specs**: Use `commands/write-spec/` and `commands/shape-spec/` for detailed specifications
3. **Create Tasks**: Use `commands/create-tasks/` to break specs into implementation tasks
4. **Implement**: Use `commands/implement-tasks/` with the implementer agent to build features
5. **Verify**: Built-in verification workflows ensure quality and standards compliance

## Agent-Specific Behavior

- **Implementer**: Focuses on code implementation, references `tasks.md` and marks completed tasks
- **Spec Writer**: Creates detailed specifications following structured templates
- **Verifier**: Validates implementations against specs and standards
- Always check which agent role you're operating in and follow its specific guidelines

## File Organization Conventions

- Specs live in `agent-os/specs/[spec-name]/` with planning/, verification/, and implementation artifacts
- Screenshots for UI verification go in `agent-os/specs/[spec-name]/verification/screenshots/`
- Use markdown extensively for documentation and structured data
- Follow the established naming patterns for consistency across workflows