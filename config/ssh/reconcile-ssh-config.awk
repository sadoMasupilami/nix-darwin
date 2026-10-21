# Reconciles the mutable client config with the managed fragment and prints
# the result (awk program, used by modules/ssh.nix). The caller only replaces
# ~/.ssh/config when the output differs, so a reconciled file stays untouched.
#
#   - The managed Include has to come before the first Host or Match line,
#     otherwise ssh applies it to that block only. An Include that already
#     does stays where it is, so it never fights the Coder extension, which
#     moves its own block back to the top.
#   - The obsolete DevPod include is dropped.
#   - The fragment sets SetEnv TERM=xterm-256color for every host, so that
#     line is dropped from inline `Host *` blocks. Such a block is dropped
#     only when nothing else is left in it; otherwise it keeps its header, so
#     its other options never end up under the preceding Host.
#   - Everything else, including Coder's Host blocks, passes through as is.
#
# usage: awk -v managed='Include ~/.ssh/config.d/nix-darwin.conf' \
#          -f reconcile-ssh-config.awk ~/.ssh/config

function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

# ssh keywords are case-insensitive and may be followed by "=".
function starts_block(line) {
  return tolower(line) ~ /^[[:space:]]*(host|match)([[:space:]]|=)/
}

function is_host_star(line) {
  return tolower(line) ~ /^[[:space:]]*host([[:space:]]+|[[:space:]]*=[[:space:]]*)\*[[:space:]]*$/
}

function is_directive(line) {
  return line !~ /^[[:space:]]*(#|$)/
}

function flush_preamble(    i) {
  if (!managed_seen) {
    print managed
  }
  for (i = 1; i <= preamble_n; i++) {
    print preamble[i]
  }
  in_preamble = 0
}

function flush_host_star(    i, keep) {
  keep = 0
  for (i = 1; i <= star_n; i++) {
    if (is_directive(star[i])) {
      keep = 1
    }
  }
  if (keep) {
    print star_header
  }
  # A dropped block takes its blank lines along; its comments stay.
  for (i = 1; i <= star_n; i++) {
    if (keep || star[i] !~ /^[[:space:]]*$/) {
      print star[i]
    }
  }
  in_host_star = 0
  star_n = 0
}

BEGIN {
  # An empty value would match, and drop, every blank line.
  if (managed == "") {
    print "reconcile-ssh-config.awk: -v managed=... is required" > "/dev/stderr"
    failed = 1
    exit 2
  }
  in_preamble = 1
}

{
  line = $0

  if (line ~ /^[[:space:]]*Include[[:space:]]+~\/\.config\/devpod\/ssh\.config[[:space:]]*$/) {
    next
  }

  if (starts_block(line)) {
    if (in_preamble) {
      flush_preamble()
    }
    if (in_host_star) {
      flush_host_star()
    }
    if (is_host_star(line)) {
      in_host_star = 1
      star_header = line
    } else {
      print line
    }
    next
  }

  # Kept once, and only where it applies to every host.
  if (trim(line) == managed) {
    if (in_preamble && !managed_seen) {
      managed_seen = 1
      preamble[++preamble_n] = line
    }
    next
  }

  if (in_preamble) {
    preamble[++preamble_n] = line
  } else if (in_host_star) {
    if (line !~ /^[[:space:]]*SetEnv[[:space:]]+TERM=xterm-256color[[:space:]]*$/) {
      star[++star_n] = line
    }
  } else {
    print line
  }
}

END {
  if (failed) {
    exit 2
  }
  if (in_preamble) {
    flush_preamble()
  }
  if (in_host_star) {
    flush_host_star()
  }
}
