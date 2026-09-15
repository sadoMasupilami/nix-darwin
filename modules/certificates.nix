{
  config,
  pkgs,
  ...
}:
let
  # The Mozilla bundle that security.pki assembles. Referencing the store path
  # directly keeps the refresh independent of activation ordering.
  baseBundle = config.environment.etc."ssl/certs/ca-certificates.crt".source;

  keychainBundle = "/etc/ssl/certs/keychain-ca.pem";
  fullBundle = "/etc/ssl/certs/ca-bundle-full.crt";

  refreshCaBundle = pkgs.writeShellApplication {
    name = "refresh-ca-bundle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.openssl
    ];
    text = ''
      # Mirrors the certificates macOS trusts system-wide into PEM bundles that
      # OpenSSL-based tools can read. The System keychain stays the only place a
      # certificate has to be trusted; wget, python and friends follow it from
      # here instead of needing their own import.
      if [ "$(id -u)" -ne 0 ]; then
        echo "refresh-ca-bundle: must run as root" >&2
        exit 1
      fi

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      /usr/bin/security find-certificate -a -p \
        /Library/Keychains/System.keychain > "$work/all.pem" 2>/dev/null || true

      # One file per certificate, so each can be checked against the trust
      # settings on its own.
      awk -v dir="$work" '
        /-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/cert-%04d.pem", dir, n) }
        n { print > f }
      ' "$work/all.pem"

      : > "$work/keychain.pem"
      kept=0
      skipped=0
      for cert in "$work"/cert-*.pem; do
        [ -e "$cert" ] || continue
        # find-certificate dumps the whole keychain, including machine
        # identities and anything explicitly distrusted. verify-cert applies the
        # real trust settings, so only what macOS actually honours gets through.
        if /usr/bin/security verify-cert -q -c "$cert" -p basic >/dev/null 2>&1 \
          && openssl x509 -in "$cert" -outform pem >> "$work/keychain.pem" 2>/dev/null; then
          kept=$((kept + 1))
        else
          skipped=$((skipped + 1))
        fi
      done

      cat ${baseBundle} "$work/keychain.pem" > "$work/full.crt"

      install -m 0644 "$work/keychain.pem" ${keychainBundle}
      install -m 0644 "$work/full.crt" ${fullBundle}

      echo "refresh-ca-bundle: $kept keychain certificate(s) trusted, $skipped skipped"
    '';
  };
in
{
  # Available as a command so a newly imported certificate can be picked up with
  # `sudo refresh-ca-bundle` instead of a full rebuild.
  environment.systemPackages = [ refreshCaBundle ];

  # security.pki only feeds /etc/ssl/certs/ca-certificates.crt, which is a
  # read-only store path, so the merge happens after the rest of activation.
  system.activationScripts.postActivation.text = ''
    ${refreshCaBundle}/bin/refresh-ca-bundle
  '';

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
