import { Hono } from "hono";

/**
 * Section 4 owns voice routes. Stub so the app mounts cleanly until that work lands.
 */
export const voiceRoutes = new Hono();

voiceRoutes.post("/voice/tts", (c) =>
  c.json({ error: { code: "internal", message: "Voice TTS not implemented (Section 4)" } }, 501),
);

voiceRoutes.post("/voice/stt", (c) =>
  c.json({ error: { code: "internal", message: "Voice STT not implemented (Section 4)" } }, 501),
);
