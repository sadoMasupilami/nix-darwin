{
  # macOS runs nix-gc-recent as a root daemon; standalone Home Manager can only
  # schedule a user job. Old generations of this user's profiles, Home
  # Manager's included, are GC roots, so the job first deletes the ones older
  # than 14 days (the age nix-gc-recent uses) and then collects all unreachable
  # store paths. The timer needs a systemd user session; without one it is
  # installed but never runs.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "1h";
    options = "--delete-older-than 14d";
  };
}
