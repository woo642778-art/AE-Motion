#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "Sources" / "AEMotionExtensionsHost"


class BatchAHostContractTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (HOST / name).read_text(encoding="utf-8")

    def test_bootstrap_is_main_actor_and_bounded(self) -> None:
        bootstrap = self.read("Bootstrap.swift")
        coordinator = self.read("HostBootstrapCoordinator.swift")
        self.assertIn("Task { @MainActor", bootstrap)
        self.assertIn("maximumAttempts = 40", coordinator)
        self.assertIn("runtimeInstalled", coordinator)
        self.assertIn("contextualInstalled", coordinator)
        self.assertIn("authInstalled", coordinator)

    def test_google_callback_repair_is_bounded_and_does_not_fabricate_session(self) -> None:
        callback = self.read("GoogleSignInCallbackRepair.swift")
        timeout = self.read("AuthenticationTimeoutGuard.swift")
        self.assertIn("application:openURL:options:", callback)
        self.assertIn("GIDSignIn", callback)
        self.assertIn("handleURL:", callback)
        self.assertIn("com.googleusercontent.apps.", callback)
        self.assertIn("timeout: TimeInterval = 25", timeout)
        forbidden = ["FirebaseAuth.signIn", "fakeCredential", "fabricatedSession"]
        for token in forbidden:
            self.assertNotIn(token, callback + timeout)

    def test_watermark_repair_only_refreshes_existing_state(self) -> None:
        source = self.read("WatermarkStateRefresh.swift")
        for controller in ["ProjectEditVC", "ExportVC", "ExportPreviewVC"]:
            self.assertIn(controller, source)
        self.assertIn("updateWatermarkView", source)
        for forbidden in [
            "NoWatermarkImpl",
            "subscriptionTier =",
            "isPremium = true",
            "hasSubscription = true",
        ]:
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
