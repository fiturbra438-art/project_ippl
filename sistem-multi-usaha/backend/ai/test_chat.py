import os
import unittest
from unittest.mock import patch

from pydantic import ValidationError

from app.schemas.ai import ChatAiRequest
from app.services.insight_ai import ProviderUnavailable, bounded_setting, generate_reply


class ChatTests(unittest.TestCase):
    def test_message_alias(self):
        self.assertEqual(ChatAiRequest(pesan="hello").chat_message(), "hello")
        self.assertEqual(ChatAiRequest(message="hello").chat_message(), "hello")

    def test_invalid_messages(self):
        for payload in ({}, {"message": " "}, {"message": "a", "pesan": "b"},
                        {"message": "a", "conversation_id": 0}):
            with self.assertRaises(ValidationError):
                ChatAiRequest(**payload)

    def test_disabled_mode_is_explicit(self):
        with patch.dict(os.environ, {"AI_CHAT_MODE": "disabled"}):
            reply, source = generate_reply("hello", [], {
                "summary": {"units": 1, "products": 2, "revenue": 3},
                "low_stock_first_20": [],
            })
        self.assertIn("dinonaktifkan", reply)
        self.assertEqual(source, "deterministic-disabled")

    def test_missing_credentials_never_fallback(self):
        with patch.dict(os.environ, {"AI_CHAT_MODE": "openai", "AI_API_KEY": ""}):
            with self.assertRaises(ProviderUnavailable):
                generate_reply("hello", [], {})

    def test_bounds(self):
        with patch.dict(os.environ, {"TEST_LIMIT": "999"}):
            self.assertEqual(bounded_setting("TEST_LIMIT", 20, 1, 25), 25)


if __name__ == "__main__":
    unittest.main()
