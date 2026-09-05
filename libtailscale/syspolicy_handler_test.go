// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package libtailscale

import (
	"testing"

	"tailscale.com/util/syspolicy/pkey"
)

func TestMWEControlURLPolicy(t *testing.T) {
	store := new(syspolicyStore)
	got, err := store.ReadString(pkey.ControlURL)
	if err != nil {
		t.Fatalf("ReadString(ControlURL): %v", err)
	}
	if got != mweControlURL {
		t.Fatalf("ReadString(ControlURL) = %q, want %q", got, mweControlURL)
	}
}
