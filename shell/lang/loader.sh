#!/usr/bin/env bash
# =============================================================================
# Compatibility stub — DO NOT SOURCE FROM NEW CODE
# =============================================================================
# Older installed versions (v1.2.0 - v1.2.4) hard-coded "loader" into the
# language-file download loop inside install.sh's self-update path. Their
# update flow expects shell/lang/loader.sh to exist at the new release tag;
# a 404 there aborts the in-place update and strands the user on the old
# version (the script then auto-restores from backup, masking the issue).
#
# This file ships as an intentional no-op so those legacy update loops
# complete with HTTP 200 and finish swapping in the new install.sh. Once
# users land on >= v1.2.6 their script no longer fetches this file.
#
# i18n itself lives entirely in lib/i18n.sh. Nothing in current install.sh
# sources loader.sh.
#
# Removing this file will re-strand every user still on v1.2.0 - v1.2.4.
# Don't.
# =============================================================================

:
