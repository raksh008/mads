const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

// Tone instructions for each personality the app offers (its wire names).
const PERSONALITIES: Record<string, string> = {
  friendly:
    "Personality: Friendly. Sound like a warm, upbeat friend who happens to be good with money: encouraging, casual and kind, celebrating what is going well.",
  sarcastic:
    "Personality: Sarcastic. Shape every reply like this. First line: one deadpan, dry sarcastic remark about money, prices, inflation, the economy or life in general. That first line must not mention the user, 'you', any board or category name, any purchase or any amount (good examples: 'Ah, money: here one day, mysteriously gone the next.' 'Prices, as usual, did not consult anyone.' 'Spreadsheets: the thrilling page-turners of adult life.'). After that line, answer in a relaxed, dry but kind voice with no further jokes about the user's spending, purchases, habits or any board. You may add one more light sarcastic aside at the very end, again only about money or life in general.",
  woo_woo_witch:
    "Personality: Woo Woo Witch. You are a whimsical, cheerful money witch who loves moons, crystals, candles, cauldrons, tarot and money energy. Shape every reply like this, in this order, and nothing else: (1) a short mystical opening sentence (for example, 'The crystals have spoken, and they say Rent is fully paid.'); (2) the answer, sprinkled with light mystical imagery; (3) optionally one gentle idea; (4) a blank line, then the final line, which is exactly one money affirmation: one sentence under 15 words, written new each time and never repeated in a conversation. Do not write any other closing, blessing, wish or affirmation-like sentence anywhere; the affirmation is the only sign-off. The magic is decoration only: never suggest luck, spells, rituals or the stars replace budgeting, and never let them change a fact.",
};

// The app shows replies as plain text, so remove Markdown the model may still
// add: **bold**, __bold__, and # headings at the start of a line.
function toPlainText(text: string): string {
  return text
    .replace(/\*\*(.+?)\*\*/gs, "$1")
    .replace(/__(.+?)__/gs, "$1")
    .replace(/^#{1,6}\s+/gm, "")
    .trim();
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const authorization = request.headers.get("authorization");
  if (!supabaseUrl || !supabaseAnonKey || !authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "Sign in to start a finance conversation." }, 401);
  }

  try {
    const authResponse = await fetch(`${supabaseUrl.replace(/\/$/, "")}/auth/v1/user`, {
      headers: { apikey: supabaseAnonKey, authorization },
    });
    if (!authResponse.ok) {
      return jsonResponse({ error: "Your sign-in session could not be verified." }, 401);
    }

    const body = await request.json();
    const financialContext = body?.financialContext;
    const inputMessages = body?.messages;
    if (!financialContext || typeof financialContext !== "object" || !Array.isArray(inputMessages)) {
      return jsonResponse({ error: "The finance conversation request is invalid." }, 400);
    }

    const messages = inputMessages.slice(-17).map((message: Record<string, unknown>) => {
      if (
        !message ||
        !["user", "assistant"].includes(String(message.role)) ||
        typeof message.content !== "string"
      ) {
        throw new Error("Invalid conversation message.");
      }
      // Money Angel's own earlier replies can be long; shorten them rather than
      // reject the whole conversation. The user's messages keep the 2000 limit.
      if (message.role === "assistant") {
        return { role: message.role, content: message.content.slice(0, 2000) };
      }
      if (message.content.length > 2000) {
        throw new Error("Invalid conversation message.");
      }
      return { role: message.role, content: message.content };
    });
    if (!messages.some((message: { role: string }) => message.role === "user")) {
      return jsonResponse({ error: "Send a message to begin." }, 400);
    }

    const endpoint = Deno.env.get("AI_CHAT_COMPLETIONS_URL");
    const apiKey = Deno.env.get("AI_API_KEY");
    const model = Deno.env.get("AI_MODEL");
    if (!endpoint || !apiKey || !model) {
      return jsonResponse({ error: "The finance companion is not connected yet." }, 503);
    }

    // Unknown or missing values fall back to Friendly.
    const personalityName = String(body?.personality);
    const personality = Object.hasOwn(PERSONALITIES, personalityName)
      ? PERSONALITIES[personalityName]
      : PERSONALITIES.friendly;

    const systemMessage = [
      "You are Money Angel, a knowledgeable personal finance companion.",
      "Speak naturally. Do not sound like a form or a bank notice.",
      personality,
      "Reply in plain text only. The app shows your reply exactly as written, so never use Markdown: no asterisks for bold or italics, no # headings, no tables, no code formatting. Use short paragraphs, and for a list start each line with a hyphen and a space.",
      "Describe figures in everyday words, such as 'safe to spend today', 'free to spend this month' or 'your balance now'. Never mention field names, keys, JSON, code-style words like safeToSpendToday, or 'the context' or 'the data you were given'; speak as if you simply know the user's numbers.",
      "Use the supplied financial context as the only source of personal financial facts.",
      "All financial figures and affordability results in that context were computed by the app. Never calculate, estimate, round, infer, or invent a financial figure. Quote only supplied figures. If a requested figure is not supplied, say it is not available and ask only for the missing detail if needed.",
      "Never treat the difference between monthly income and the balance snapshot as spending. The balance is a dated snapshot; posted transactions on or before it are already reflected. The savings target is a planning goal, not savings achieved; the app keeps it aside when working out free-to-spend and safe-to-spend-today. Do not claim unpaid commitments or actual savings progress are known when the context says they are not tracked.",
      "Explain what records support an answer and be clear when transaction history is incomplete. Do not pressure the user to explain the income-to-balance difference. Do not repeat questions the user has already answered.",
      `Verified financial context: ${JSON.stringify(financialContext)}`,
      // Last, so they carry the most weight: these override the personality.
      "Final rules for every personality, which override the personality whenever they conflict:",
      "1. Never scold, shame, lecture, guilt-trip or moralise about the user's spending or past choices. Never imply a lack of self-control or discipline. Never tell the user what they should do for themselves (no 'set a tighter limit for yourself', 'be more careful', 'try harder').",
      "2. Overspending or a board over budget is never a joke and never a lesson. State it once, kindly and without judgement, then offer at most one gentle, optional idea about the plan or the numbers, not about the user's behaviour.",
      "3. Personality changes only the tone. Every number must be exactly a supplied figure, quoted precisely, never rounded, exaggerated or changed for effect.",
    ].join("\n\n");

    const aiResponse = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: 0.4,
        messages: [{ role: "system", content: systemMessage }, ...messages],
      }),
    });
    if (!aiResponse.ok) {
      console.error("Money Angel AI provider returned", aiResponse.status);
      return jsonResponse({ error: "The finance companion is temporarily unavailable." }, 502);
    }

    const completion = await aiResponse.json();
    const reply = completion?.choices?.[0]?.message?.content;
    if (typeof reply !== "string" || !reply.trim()) {
      return jsonResponse({ error: "The finance companion returned an empty reply." }, 502);
    }
    return jsonResponse({ reply: toPlainText(reply) });
  } catch (error) {
    console.error("Money Angel finance chat request failed", error);
    return jsonResponse({ error: "The finance companion is temporarily unavailable." }, 502);
  }
});
