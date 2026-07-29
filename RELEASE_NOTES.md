# Release Notes

Release notes for `container-ee-wunder-toolbox-ubi9` are published with GitHub Releases:

https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/releases

This generated file exists so repository-local documentation has a stable release-notes entry point without maintaining
a committed changelog. The authoritative per-version notes remain the signed GitHub Releases and their attached release
evidence.

## Pending release assurance fix

The release workflow now removes the completed multi-architecture Buildx
cache before downloading the Trivy vulnerability database and scanning the
published image. This preserves the fail-closed release scan while preventing
the GitHub-hosted runner from exhausting its filesystem after a successful
multi-platform build.
