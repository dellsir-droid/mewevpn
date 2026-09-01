// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package com.tailscale.ipn

/** Build-specific endpoints for the M-WE private network client. */
object MWeConfig {
  const val CONTROL_URL = "https://hs.m-we.org"

  // Headscale, rather than the Android client, performs the OpenID Connect exchange. Its server
  // configuration uses this issuer and sends the browser here after CONTROL_URL begins login.
  const val OIDC_ISSUER = "https://oidc.m-we.org"
}
