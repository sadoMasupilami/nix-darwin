{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The Mozilla bundle that security.pki assembles. Referencing the store path
  # directly keeps the refresh independent of activation ordering.
  baseBundle = config.environment.etc."ssl/certs/ca-certificates.crt".source;

  keychainBundle = "/etc/ssl/certs/keychain-ca.pem";
  fullBundle = "/etc/ssl/certs/ca-bundle-full.crt";
  logFile = "/var/log/refresh-ca-bundle.log";

  user = config.system.primaryUser;
  userArg = lib.escapeShellArg user;
  loginKeychain = "${config.users.users.${user}.home}/Library/Keychains/login.keychain-db";

  # Runs as the user whose trust is mirrored, so trustd applies that user's
  # trust settings on top of the admin and system domains.
  keychainTrustedCas = pkgs.writeShellApplication {
    name = "keychain-trusted-cas";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.openssl
    ];
    text = ''
      # Prints the keychain CA certificates, and self-signed certificates that
      # are their own anchor, that macOS trusts for the calling user as PEM.
      #
      # usage: keychain-trusted-cas [login-keychain]
      login_keychain=''${1-}

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      # An evaluation that cannot reach trustd rejects every certificate and
      # would silently empty the bundle, so Apple's own root has to pass first.
      /usr/bin/security find-certificate -c 'Apple Root CA' -p \
        /System/Library/Keychains/SystemRootCertificates.keychain > "$work/sentinel.pem"
      if ! /usr/bin/security verify-cert -q -L -c "$work/sentinel.pem" -p basic >/dev/null 2>&1; then
        echo "keychain-trusted-cas: trust evaluation is unavailable" >&2
        exit 1
      fi

      # SHA-1 fingerprints of certificates with their own admin or user trust
      # settings, as set by `security add-trusted-cert` or "Always Trust".
      # Only the login keychain filter below uses them.
      : > "$work/explicit"
      if [ -n "$login_keychain" ]; then
        # A domain without trust settings is fine. Any other failure means this
        # context cannot read the settings it is meant to mirror, and going on
        # would publish bundles without the user's CAs, so give up instead.
        # security localizes the message, so it supplies the expected one too.
        no_settings=$(/usr/bin/security error -25263 2>&1 \
          | sed -n 's/^Error: [^ ]* -25263 //p' || true)
        no_settings=''${no_settings:-No Trust Settings were found.}
        export_trust_settings() {
          local err
          if ! err=$(/usr/bin/security trust-settings-export "$@" 2>&1 >/dev/null); then
            case "$err" in
              *"$no_settings"*) ;;
              *)
                echo "keychain-trusted-cas: cannot read the trust settings: $err" >&2
                exit 1
                ;;
            esac
          fi
        }
        export_trust_settings -d "$work/admin.plist"
        export_trust_settings "$work/user.plist"
        for plist in "$work/admin.plist" "$work/user.plist"; do
          [ -s "$plist" ] || continue
          /usr/bin/plutil -convert xml1 -o - "$plist" \
            | sed -n 's|^[[:space:]]*<key>\([0-9A-F]\{40\}\)</key>$|\1|p' >> "$work/explicit"
        done
      fi

      mkdir "$work/system" "$work/login"
      /usr/bin/security find-certificate -a -p \
        /Library/Keychains/System.keychain > "$work/system.pem" 2>/dev/null || true
      : > "$work/login.pem"
      if [ -n "$login_keychain" ]; then
        /usr/bin/security find-certificate -a -p \
          "$login_keychain" > "$work/login.pem" 2>/dev/null || true
      fi

      # One file per certificate, so each can be checked on its own.
      for keychain in system login; do
        awk -v dir="$work/$keychain" '
          /-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/cert-%04d.pem", dir, n) }
          n { print > f }
        ' "$work/$keychain.pem"
      done

      : > "$work/seen"
      for cert in "$work"/system/cert-*.pem "$work"/login/cert-*.pem; do
        [ -e "$cert" ] || continue
        fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 2>/dev/null || true)
        fingerprint=$(printf '%s' "''${fingerprint#*=}" | tr -d ':' | tr '[:lower:]' '[:upper:]')
        [ -n "$fingerprint" ] || continue
        # Mail adds the S/MIME chain of every signed message to the login
        # keychain, so only certificates trusted on their own count there.
        case "$cert" in
          "$work"/login/*) grep -Fqx "$fingerprint" "$work/explicit" || continue ;;
        esac
        grep -Fqx "$fingerprint" "$work/seen" && continue

        # Machine and device identities chain to trusted roots as well, but
        # must never become trust anchors, so only CAs qualify. So does a
        # certificate that is its own anchor: a self-signed server
        # certificate set to "Always Trust", or a v1 root without
        # extensions. Its self-signature has to verify against itself alone;
        # a matching name is not enough. verify-cert then applies the trust
        # settings, including explicit distrust.
        constraints=$(openssl x509 -in "$cert" -noout -ext basicConstraints 2>/dev/null || true)
        case "$constraints" in
          *CA:TRUE*) ;;
          *)
            openssl verify -no-CApath -no-CAstore -check_ss_sig \
              -CAfile "$cert" "$cert" >/dev/null 2>&1 || continue
            ;;
        esac
        if /usr/bin/security verify-cert -q -L -c "$cert" -p basic >/dev/null 2>&1 \
          && openssl x509 -in "$cert" -outform pem 2>/dev/null; then
          printf '%s\n' "$fingerprint" >> "$work/seen"
        fi
      done
    '';
  };

  refreshCaBundle = pkgs.writeShellApplication {
    name = "refresh-ca-bundle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
      pkgs.openssl
    ];
    text = ''
      # Mirrors the CA certificates macOS trusts for ${user} into PEM bundles
      # that OpenSSL-based tools can read. The keychain stays the only place a
      # certificate has to be trusted; wget, python and friends follow it from
      # here instead of needing their own import.
      #
      # usage: refresh-ca-bundle [--dry-run]
      #   --dry-run  list what would be mirrored; needs no root, changes nothing
      dry_run=false
      case "''${1-}" in
        "") ;;
        --dry-run) dry_run=true ;;
        *)
          echo 'usage: refresh-ca-bundle [--dry-run]' >&2
          exit 2
          ;;
      esac

      if [ "$dry_run" = false ] && [ "$(id -u)" -ne 0 ]; then
        echo "refresh-ca-bundle: must run as root (use --dry-run to inspect)" >&2
        exit 1
      fi

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      # "Always Trust" in Keychain Access lands in the user's trust domain,
      # which only that user's trustd agent serves; root sees the admin and
      # system domains alone. launchctl asuser reaches the agent from the
      # daemon's system context as well as from activation.
      as_user() {
        if [ "$(id -u)" -eq 0 ]; then
          /bin/launchctl asuser "$(id -u ${userArg})" /usr/bin/sudo -u ${userArg} --set-home -- "$@"
        else
          "$@"
        fi
      }

      # Before login, at boot for instance, ${user} has no session whose trust
      # agent could answer, and the evaluation would miss the user's CAs.
      # Existing bundles stay until a later run; a first run still creates
      # them below.
      if [ "$dry_run" = false ] && [ -e ${keychainBundle} ] && [ -e ${fullBundle} ] \
        && ! /bin/launchctl print "gui/$(id -u ${userArg})" >/dev/null 2>&1; then
        echo "refresh-ca-bundle: ${user} has no login session; previous bundles kept"
        exit 0
      fi

      view="trust settings of ${user}"
      if ! as_user ${keychainTrustedCas}/bin/keychain-trusted-cas \
        ${lib.escapeShellArg loginKeychain} > "$work/keychain.pem"; then
        if [ "$dry_run" = true ]; then
          exit 1
        fi
        # Falling back to root's narrower view on every failed run would make
        # user-trusted CAs come and go, so existing bundles stay as they are.
        if [ -e ${keychainBundle} ] && [ -e ${fullBundle} ]; then
          echo "refresh-ca-bundle: cannot evaluate trust as ${user}; previous bundles kept" >&2
          exit 1
        fi
        # Without any bundle the session variables below would point nowhere.
        echo "refresh-ca-bundle: cannot evaluate trust as ${user}; using admin and system trust only" >&2
        view="admin and system trust settings"
        ${keychainTrustedCas}/bin/keychain-trusted-cas > "$work/keychain.pem"
      fi
      count=$(grep -c -- '-----BEGIN CERTIFICATE-----' "$work/keychain.pem" || true)

      if [ "$dry_run" = true ]; then
        if [ "$count" -gt 0 ]; then
          openssl crl2pkcs7 -nocrl -certfile "$work/keychain.pem" \
            | openssl pkcs7 -print_certs -noout
        fi
        echo "refresh-ca-bundle: $count keychain CA certificate(s) from the $view; dry run, nothing written"
        exit 0
      fi

      cat ${baseBundle} "$work/keychain.pem" > "$work/full.crt"

      # Renaming within /etc/ssl/certs is atomic, so readers never see a
      # partial bundle. Unchanged bundles are left alone.
      changed=false
      publish() {
        local tmp
        cmp -s "$1" "$2" && return 0
        tmp=$(mktemp "$2.XXXXXX")
        if ! { cat "$1" > "$tmp" && chmod 0644 "$tmp" && mv -f "$tmp" "$2"; }; then
          rm -f "$tmp"
          return 1
        fi
        changed=true
      }
      publish "$work/keychain.pem" ${keychainBundle}
      publish "$work/full.crt" ${fullBundle}

      state=unchanged
      [ "$changed" = false ] || state=updated
      echo "refresh-ca-bundle: $count keychain CA certificate(s) from the $view; bundles $state"
    '';
  };
in
{
  # Available as a command so a newly imported certificate can be picked up with
  # `sudo refresh-ca-bundle` without waiting for the daemon below.
  environment.systemPackages = [ refreshCaBundle ];

  # security.pki only feeds /etc/ssl/certs/ca-certificates.crt, which is a
  # read-only store path, so the merge happens after the rest of activation.
  # It runs synchronously so the bundles exist before the session variables
  # below are first used. A failure keeps the previous bundles and must not
  # abort the switch: /run/current-system is relinked only after this.
  system.activationScripts.postActivation.text = ''
    ${refreshCaBundle}/bin/refresh-ca-bundle \
      || printf >&2 '\e[1;31mwarning: refresh-ca-bundle failed, the previous CA bundles stay in place\e[0m\n'
  '';

  # Removals and distrust have to reach OpenSSL, Node and requests without an
  # apply. Imports and deletions rewrite the System keychain; trust settings
  # live in trustd's private store, which cannot be watched, so the interval
  # catches those.
  launchd.daemons.refresh-ca-bundle = {
    command = "${refreshCaBundle}/bin/refresh-ca-bundle";
    serviceConfig = {
      WatchPaths = [ "/Library/Keychains/System.keychain" ];
      StartInterval = 3600;
      RunAtLoad = true;
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };

  # Every run logs a summary line, and the daemon runs at least hourly.
  system.newsyslog = {
    enable = true;
    files.refresh-ca-bundle = [
      {
        logfilename = logFile;
        owner = "root";
        group = "wheel";
        count = 3;
        size = "256";
        flags = [
          "N"
          "J"
        ];
      }
    ];
  };

  environment.variables = {
    # OpenSSL consumers that are not Keychain-aware: nix-built tools such as
    # wget, and Homebrew's own OpenSSL behind python3 and friends.
    NIX_SSL_CERT_FILE = fullBundle;
    SSL_CERT_FILE = fullBundle;
    # requests ships its own certifi bundle and ignores SSL_CERT_FILE.
    REQUESTS_CA_BUNDLE = fullBundle;
    # Node appends this to its built-in store, so only the extras belong here.
    NODE_EXTRA_CA_CERTS = keychainBundle;
  };

  # curl and git keep using Secure Transport, which already reads the Keychain,
  # so CURL_CA_BUNDLE and GIT_SSL_CAINFO are deliberately left unset.
}
