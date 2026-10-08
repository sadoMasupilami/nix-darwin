{ claudeModsSource, ... }:
{
  # Claude Code loads every folder in ~/.claude/skills that holds a
  # .claude-plugin/plugin.json as a plugin (<name>@skills-dir). Linking the
  # whole folder keeps the mod's hooks, types and manifest together.
  home.file.".claude/skills/token-weather".source =
    "${claudeModsSource}/claude-code/mods/token-weather";
  home.file.".claude/skills/blast-radius".source =
    "${claudeModsSource}/claude-code/mods/blast-radius";
  # Own mod, kept in this repo: rate-limit windows and session cost.
  home.file.".claude/skills/usage-meter".source = ../config/claude-mods/usage-meter;
}
